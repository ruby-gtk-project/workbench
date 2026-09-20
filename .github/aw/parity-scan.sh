#!/usr/bin/env bash
# Parity scan: extract the user-visible inventory from an upstream GTK app and
# check the Ruby port for each item.
#
# The port has no .ui files — widgets are built in Ruby — so item counts cannot
# be compared side by side. Instead upstream is treated as authoritative: every
# item is reduced to an identifying literal (an action name, an accelerator, a
# settings key, a msgid, an app id) and the port is searched for it. Those
# literals have to survive a port verbatim, which makes them a reliable signal
# across Vala, C, Python, JavaScript and Rust upstreams.
#
# Usage: parity-scan.sh <upstream-tree> <port-tree> <out-dir>
set -uo pipefail

UPSTREAM=$1
PORT=$2
OUT=$3
mkdir -p "$OUT"

# Files worth reading on each side. Everything else (build output, vendored
# deps, .git, translations we handle separately) is noise.
srcfiles() {
  find "$1" -type f \
    -not -path '*/.git/*' -not -path '*/po/*' -not -path '*/_build/*' \
    -not -path '*/build/*' -not -path '*/node_modules/*' -not -path '*/vendor/*' \
    -not -path '*/subprojects/*' -not -path '*/.bundle/*' \
    \( -name '*.ui' -o -name '*.blp' -o -name '*.xml' -o -name '*.vala' \
       -o -name '*.c' -o -name '*.h' -o -name '*.py' -o -name '*.js' \
       -o -name '*.rs' -o -name '*.rb' -o -name '*.in' -o -name '*.desktop*' \
       -o -name '*.gresource*' -o -name '*.json' \) 2>/dev/null
}

srcfiles "$UPSTREAM" > "$OUT/upstream-files.txt"
srcfiles "$PORT"     > "$OUT/port-files.txt"

# extract <name> <regex> <post-filter-sed> — pulls distinct literals from upstream
extract() {
  local name=$1 re=$2 post=${3:-cat}
  # shellcheck disable=SC2046
  grep -rhoEI "$re" $(cat "$OUT/upstream-files.txt") 2>/dev/null \
    | eval "$post" | sed 's/^ *//; s/ *$//' | grep -v '^$' \
    | sort -u > "$OUT/upstream-$name.txt"
}

# GAction names: "app.quit", "win.new-window". Appear in .ui menus, accel
# registrations and activate calls alike.
extract actions '"(app|win)\.[A-Za-z0-9_.-]+"' 'tr -d \"'

# Accelerators: "<Primary>n", "<Control><Shift>w".
extract accels '"<(Primary|Control|Ctrl|Shift|Alt|Super|Meta)>[^"]*"' \
  'tr -d \" | tr " " "\n" | grep "^<"'

# GSettings keys — the schema is the list of every preference the app has.
grep -rhoEI '<key +name="[^"]+"' $(cat "$OUT/upstream-files.txt") 2>/dev/null \
  | sed 's/.*name="//; s/"$//' | sort -u > "$OUT/upstream-settings.txt"

# Menu item and UI labels, translatable => user-visible.
{
  # GtkBuilder XML
  grep -rhoEI '<attribute +name="label"[^>]*>[^<]+' $(cat "$OUT/upstream-files.txt") 2>/dev/null \
    | sed 's/.*>//'
  # Blueprint: label: _("Save"), title: C_("ctx", "Save")
  grep -rhoEI '(label|title|tooltip-text|placeholder-text): *(C?_\()?"[^"]+"' \
    $(cat "$OUT/upstream-files.txt") 2>/dev/null \
    | sed 's/.*"\([^"]*\)".*/\1/'
} | sed 's/^ *//; s/ *$//' | grep -v '^$' | sort -u > "$OUT/upstream-menulabels.txt"

# Widget types the UI is built from. AdwFoo/GtkFoo -> Adw::Foo/Gtk::Foo for the
# port-side search, since that is how ruby-gnome spells them.
{
  # GtkBuilder XML: class="AdwToastOverlay"
  grep -rhoEI 'class="(Adw|Gtk)[A-Za-z]+"' $(cat "$OUT/upstream-files.txt") 2>/dev/null \
    | sed 's/class="//; s/"$//'
  # Blueprint: Adw.ToastOverlay { , and GJS/Python: new Adw.ToastOverlay(
  grep -rhoEI '\b(Adw|Gtk)\.[A-Z][A-Za-z]+' $(cat "$OUT/upstream-files.txt") 2>/dev/null \
    | tr -d '.'
} | sort -u > "$OUT/upstream-widgets.txt"

# Command line options.
grep -rhoEI '"--[a-z0-9][a-z0-9-]*"' $(cat "$OUT/upstream-files.txt") 2>/dev/null \
  | tr -d '"' | sort -u > "$OUT/upstream-cli.txt"

# Translatable strings. The .pot is the complete list when it exists; otherwise
# fall back to _("...") in source. This is the broadest completeness proxy —
# user-visible text is user-visible features.
if ls "$UPSTREAM"/po/*.pot >/dev/null 2>&1; then
  grep -h '^msgid "' "$UPSTREAM"/po/*.pot | sed 's/^msgid "//; s/"$//' \
    | sed 's/\\"/"/g; s/\\\\/\\/g' \
    | grep -v '^$' | sort -u > "$OUT/upstream-strings.txt"
else
  grep -rhoEI '_\("[^"]{3,}"\)' $(cat "$OUT/upstream-files.txt") 2>/dev/null \
    | sed 's/^_("//; s/")$//' | sort -u > "$OUT/upstream-strings.txt"
fi

# Application id — appears in the desktop file, metainfo, schema paths and the
# GtkApplication construction. The port must use its own id or the original's,
# consistently; the agent judges which.
grep -rhoEI '[a-z][a-z0-9]*(\.[A-Za-z][A-Za-z0-9]+){2,}' \
  $(find "$UPSTREAM" -maxdepth 2 \( -name '*.desktop*' -o -name '*metainfo*' -o -name '*appdata*' \) 2>/dev/null) 2>/dev/null \
  | sort | uniq -c | sort -rn | head -5 | awk '{print $2}' > "$OUT/upstream-appid.txt"

# Packaged data files that have to exist on the port side in some form.
for pat in '*.desktop*' '*metainfo*' '*appdata*' '*.gschema.xml*' '*.service.in' '*.gresource.xml'; do
  find "$UPSTREAM" -name "$pat" -not -path '*/.git/*' 2>/dev/null | sed "s|^$UPSTREAM/||"
done | sort -u > "$OUT/upstream-datafiles.txt"

# --- port side: for each upstream literal, is there evidence in the port? ----

PORTBLOB="$OUT/.portblob"
# shellcheck disable=SC2046
cat $(cat "$OUT/port-files.txt") 2>/dev/null > "$PORTBLOB"

check() {                       # check <category> [sed-transform-for-search]
  local cat=$1 xform=${2:-cat}
  local src="$OUT/upstream-$cat.txt"
  : > "$OUT/missing-$cat.txt"
  : > "$OUT/found-$cat.txt"
  [ -s "$src" ] || return 0
  while IFS= read -r item; do
    needle=$(printf '%s' "$item" | eval "$xform")
    [ -n "$needle" ] || continue
    if grep -qF -- "$needle" "$PORTBLOB" 2>/dev/null; then
      printf '%s\n' "$item" >> "$OUT/found-$cat.txt"
    else
      printf '%s\n' "$item" >> "$OUT/missing-$cat.txt"
    fi
  done < "$src"
}

check actions
check accels
check settings
check menulabels
check cli
check strings
# AdwToastOverlay -> ::ToastOverlay. Match on the type name rather than the
# namespace: ruby-gnome spells libadwaita "Adwaita::", not "Adw::".
check widgets "sed -E 's/^(Adw|Gtk)/::/'"

# Data files are matched by kind, not path — the port may relocate them.
: > "$OUT/missing-datafiles.txt"; : > "$OUT/found-datafiles.txt"
while IFS= read -r f; do
  base=$(basename "$f" | sed 's/\.in$//')
  if find "$PORT" -name "*$(printf '%s' "$base" | sed 's/^[^.]*//')*" -not -path '*/.git/*' 2>/dev/null | grep -q .; then
    printf '%s\n' "$f" >> "$OUT/found-datafiles.txt"
  else
    printf '%s\n' "$f" >> "$OUT/missing-datafiles.txt"
  fi
done < "$OUT/upstream-datafiles.txt"

rm -f "$PORTBLOB"

# --- metrics.json -----------------------------------------------------------
{
  printf '{\n  "categories": {\n'
  first=1
  for cat in actions accels settings menulabels widgets cli strings datafiles; do
    total=$(wc -l < "$OUT/upstream-$cat.txt" 2>/dev/null | tr -d ' '); total=${total:-0}
    found=$(wc -l < "$OUT/found-$cat.txt" 2>/dev/null | tr -d ' '); found=${found:-0}
    miss=$(wc -l < "$OUT/missing-$cat.txt" 2>/dev/null | tr -d ' '); miss=${miss:-0}
    if [ "$total" -gt 0 ]; then pct=$((found * 100 / total)); else pct=100; fi
    [ $first -eq 1 ] || printf ',\n'; first=0
    printf '    "%s": {"upstream": %s, "found": %s, "missing": %s, "coverage": %s}' \
      "$cat" "$total" "$found" "$miss" "$pct"
  done
  printf '\n  },\n'
  printf '  "port_ruby_files": %s,\n' "$(grep -c '\.rb$' "$OUT/port-files.txt" || echo 0)"
  printf '  "upstream_source_files": %s\n' "$(wc -l < "$OUT/upstream-files.txt" | tr -d ' ')"
  printf '}\n'
} > "$OUT/metrics.json"

cat "$OUT/metrics.json"
