#!/usr/bin/env bash
# Inventory the UI components of a GTK app, per file.
#
# Output: <file>\t<kind>\t<value>\t<count>
#   kind = widget   a type that subclasses Gtk.Widget - a thing on screen
#          controller an EventController/Gesture - behaviour, not a widget
#          type      a known GTK class that is NOT a widget (model, buffer,
#                    filter, provider, layout manager, enum, record)
#          css      a CSS class attached to a widget in that file
#          css-name a GTK element name (set_css_name) - an element selector,
#                   not a class selector; compare against the port's classes
#          signal  a signal that file connects a handler to
#          action  a GAction name installed or referenced in that file
#
# Per file, not per instance: grep cannot reconstruct a widget tree. Note that
# one component is often TWO upstream files - a source file plus its .ui/.blp
# template - which the Ruby port merges into one. Union the rows of the mapped
# files before comparing; see the component-parity skill.
# The counts carry multiplicity: three AdwActionRows in a file is
# `widget Adw.ActionRow 3`. A widget built by a shared factory called from
# three places counts once here and three times on screen - read the file.
#
# Paths are printed relative to the tree, so two trees can be diffed directly.
#
# Usage: component-scan.sh <tree>
set -uo pipefail

[ $# -eq 1 ] || { echo "usage: $(basename "$0") <tree>" >&2; exit 2; }
TREE=${1%/}

# The symbol table from gir-symbols.sh, if one has been built. With it, the
# widget stream is classified against what GTK actually declares instead of a
# hand-kept strike list: Gtk.Adjustment, Gtk.StackPage and Gtk.TextTag are real
# classes that are not widgets, and no regex can know that. Without it every
# matched type stays `widget` and you strike them by reading (see the skill).
SYMBOLS=${SYMBOLS:-"$(dirname "$0")/symbols.tsv"}

classify() {
  if [ -s "$SYMBOLS" ]; then
    awk -F'\t' -v S="$SYMBOLS" '
      BEGIN {
        while ((getline line < S) > 0) {
          split(line, a, "\t"); k[a[1]] = a[2]
          # Case-folded index, so a name reconstructed from a C macro can be
          # snapped back to its canonical spelling. GTK_TYPE_GL_AREA can only
          # be un-camelled to Gtk.GlArea, but the real symbol is Gtk.GLArea -
          # and every other language spells it correctly, so without this the
          # C side of a comparison reports one missing and one extra.
          canon[tolower(a[1])] = a[1]
        }
      }
      $2 == "widget" && !($3 in k) && (tolower($3) in canon) { $3 = canon[tolower($3)] }
      $2 == "widget" && ($3 in k) {
        t = k[$3]
        if (t == "widget")          print
        else if (t == "controller") print $1 "\tcontroller\t" $3 "\t" $4
        else                        print $1 "\ttype\t" $3 "\t" $4
        next
      }
      { print }   # unknown symbol: left as widget, conservatively
    '
  else
    cat
  fi
}

srcfiles() {
  find "$TREE" -type f \
    -not -path '*/.git/*' -not -path '*/po/*' -not -path '*/_build/*' \
    -not -path '*/build/*' -not -path '*/node_modules/*' -not -path '*/vendor/*' \
    -not -path '*/subprojects/*' -not -path '*/.bundle/*' \
    -not -path '*/.claude/skills/*' -not -path '*/target/debug/*' \
    -not -path '*/test/*' -not -path '*/tests/*' -not -path '*/spec/*' \
    \( -name '*.ui' -o -name '*.ui.in' -o -name '*.blp' -o -name '*.blp.in' \
       -o -name '*.vala' -o -name '*.c' -o -name '*.h' \
       -o -name '*.py' -o -name '*.js' -o -name '*.ts' -o -name '*.rs' \
       -o -name '*.rb' \) 2>/dev/null
}

# tally <file> <kind> - reads matched values on stdin, emits deduped rows with
# counts. `awk NF` rather than `grep -v` so that empty input is not a failure
# exit under pipefail.
tally() {
  sed 's/^ *//; s/ *$//' | awk 'NF' | sort | uniq -c \
    | awk -v f="$1" -v k="$2" '{c=$1; $1=""; sub(/^ /,""); print f "\t" k "\t" $0 "\t" c}'
}

# C hides CSS class names behind constants - #define KGX_WINDOW_STYLE_ROOT
# "root" in a header, used as a bare identifier at the call site. Resolve them
# once up front so those classes are not silently lost.
MACROMAP=$(mktemp)
trap 'rm -f "$MACROMAP"' EXIT
# shellcheck disable=SC2046
grep -rhoE '#define[[:space:]]+[A-Z][A-Z0-9_]*[[:space:]]+"[^"]+"' $(srcfiles) 2>/dev/null \
  | sed -E 's/#define[[:space:]]+([A-Z][A-Z0-9_]*)[[:space:]]+"([^"]+)"/\1\t\2/' \
  | sort -u > "$MACROMAP"

srcfiles | { while IFS= read -r f; do
  rel=${f#"$TREE"/}

  # --- widgets -------------------------------------------------------------
  # Normalised to Ns.Type so that Vala `new Adw.ActionRow`, GtkBuilder
  # class="AdwActionRow", gtk-rs `adw::ActionRow` and Ruby
  # `Adwaita::ActionRow.new` all land on the same value.
  {
    # GtkBuilder objects AND template roots: <template parent="AdwBin">.
    # An app-defined template class (class="MyWidget") is deliberately not a
    # row - resolve it to the file that defines it. See the skill, Step 4.
    grep -ohE '(class|parent)="(Adw|Gtk|Vte|GtkSource|Shumate|WebKit|Panel)[A-Za-z0-9]+"' "$f" 2>/dev/null \
      | sed -E 's/.*"(Adw|Gtk|Vte|GtkSource|Shumate|WebKit|Panel)([A-Za-z0-9]+)"/\1.\2/'
    # Vala, Python, GJS, blueprint: Adw.ActionRow
    grep -ohE '\b(Adw|Gtk|Adwaita|Vte|GtkSource|Shumate|WebKit|Panel)\.[A-Z][A-Za-z0-9]+' "$f" 2>/dev/null \
      | sed -E 's/^Adwaita\./Adw./'
    # Ruby: Adwaita::ActionRow / Gtk::Box
    grep -ohE '\b(Adw|Gtk|Adwaita|Vte|GtkSource|Shumate|WebKit|Panel)::[A-Z][A-Za-z0-9]+' "$f" 2>/dev/null \
      | sed -E 's/::/./; s/^Adwaita\./Adw./'
    # gtk-rs: lowercase crate modules - gtk::Button, adw::Carousel - including
    # inside TemplateChild<gtk::Button>, which is an instance site.
    grep -ohE '\b(gtk4?|adw|libadwaita|vte|sourceview5?|shumate|webkit6?|panel)::[A-Z][A-Za-z0-9]+' "$f" 2>/dev/null \
      | sed -E 's/^gtk4?::/Gtk./; s/^(adw|libadwaita)::/Adw./; s/^vte::/Vte./
                s/^sourceview5?::/GtkSource./; s/^shumate::/Shumate./
                s/^webkit6?::/WebKit./; s/^panel::/Panel./'
    # C: GTK_TYPE_LIST_BOX / ADW_TYPE_ACTION_ROW macros, and gtk_*_new()
    # constructors. Without these the whole C source side is invisible - the
    # widget tree is in the .ui, but everything built at runtime is in here.
    {
      grep -ohE '\b(GTK|ADW|VTE)_TYPE_[A-Z0-9_]+' "$f" 2>/dev/null
      grep -ohE '\b(gtk|adw|vte)_[a-z0-9_]+_new[a-z_]*[[:space:]]*\(' "$f" 2>/dev/null \
        | sed -E 's/[[:space:]]*\($//; s/_new[a-z_]*$//' \
        | tr '[:lower:]' '[:upper:]' | sed -E 's/^(GTK|ADW|VTE)_/\1_TYPE_/'
    } | awk '
        BEGIN { m["GTK"] = "Gtk"; m["ADW"] = "Adw"; m["VTE"] = "Vte" }
        {
          ns = $0; sub(/_TYPE_.*/, "", ns)
          rest = $0; sub(/^[A-Z]+_TYPE_/, "", rest)
          n = split(tolower(rest), part, "_"); name = ""
          for (i = 1; i <= n; i++)
            name = name toupper(substr(part[i], 1, 1)) substr(part[i], 2)
          if (ns in m && name != "") print m[ns] "." name
        }'

    # Blueprint bare declarations. `using Gtk 4.0` makes Gtk the implicit
    # namespace, so the whole widget tree is written unprefixed - `Box {`,
    # `MenuButton btn {`, `content: WindowHandle {`. Without this the only
    # widgets found in a .blp are the Adw.-prefixed ones, which on a typical
    # app is four rows out of thirty.
    case "$f" in *.blp)
      {
        grep -ohE '^[[:space:]]*[A-Z][A-Za-z0-9]+([[:space:]]+[a-z_][A-Za-z0-9_]*)?[[:space:]]*\{' "$f" 2>/dev/null \
          | sed -E 's/^[[:space:]]*([A-Z][A-Za-z0-9]+).*/\1/'
        grep -ohE '[a-z][a-z0-9_-]*:[[:space:]]*[A-Z][A-Za-z0-9]+[[:space:]]*\{' "$f" 2>/dev/null \
          | sed -E 's/.*:[[:space:]]*([A-Z][A-Za-z0-9]+).*/\1/'
      } | sed 's/^/Gtk./' ;;
    esac
  } | grep -vxE 'Gtk\.Template' | tally "$rel" widget

  # --- css classes ---------------------------------------------------------
  {
    # GtkBuilder: <class name="suggested-action"/>
    grep -ohE '<class +name="[^"]+"' "$f" 2>/dev/null | sed 's/^[^"]*"//; s/"$//'
    # add_css_class ("flat") and, in C, gtk_widget_add_css_class (w, "flat")
    # where the widget comes first. Take the first quoted string either way.
    # remove_css_class counts too: a class a widget takes off is a class it
    # can wear, and the port needs the same state.
    grep -ohE '(add|remove)_(css_)?class *\([^;]*"[^"]+"' "$f" 2>/dev/null \
      | sed 's/^[^"]*"//; s/".*$//'
    grep -ohE "(add|remove)_(css_)?class *\([^;]*'[^']+'" "$f" 2>/dev/null \
      | sed "s/^[^']*'//; s/'.*\$//"
    # ... and the same call taking a #define'd constant instead of a literal.
    grep -ohE '(add|remove)_(css_)?class *\([^;]*,[[:space:]]*[A-Z][A-Z0-9_]+' "$f" 2>/dev/null \
      | sed -E 's/.*,[[:space:]]*//' \
      | while IFS= read -r macro; do
          awk -F'\t' -v m="$macro" '$1 == m { print $2 }' "$MACROMAP"
        done
    # css_classes = ["flat"] / styles ["flat"] (blueprint) /
    # .css_classes(vec!["flat"]) and .set_css_classes(&["flat"]) (gtk-rs).
    # Blueprint normally breaks these across lines, so the bracket is tracked
    # with a state machine rather than matched on one line.
    awk '/(^|[^A-Za-z_])(set_)?(css_classes|styles)[[:space:]]*[=:(]?[[:space:]]*(vec!)?[[:space:]]*&?[[:space:]]*\[/ { s = 1 }
         s { print; if (/\]/) s = 0 }' "$f" 2>/dev/null \
      | grep -ohE '"[^"]+"' | tr -d '"'
  } | tally "$rel" css

  # --- css element names ------------------------------------------------
  # gtk_widget_class_set_css_name (klass, "kgx-tab") makes the CSS selector
  # `kgx-tab { }` rather than `.kgx-tab { }`. A Ruby port has no GType to hang
  # a css name on and re-expresses these as classes, so they are their own
  # kind - comparing them against the `css` stream reports false gaps.
  {
    grep -ohE 'set_css_name *\([^;]*"[^"]+"' "$f" 2>/dev/null | sed 's/^[^"]*"//; s/".*$//'
    grep -ohE 'css_name *[=:] *"[^"]+"' "$f" 2>/dev/null | sed 's/^[^"]*"//; s/".*$//'
  } | tally "$rel" css-name

  # --- signals -------------------------------------------------------------
  # What the component responds to. Connection sites, not emissions.
  {
    # GtkBuilder: <signal name="clicked" handler="on_clicked"/>
    grep -ohE '<signal +name="[^"]+"' "$f" 2>/dev/null | sed 's/^[^"]*"//; s/"$//'
    # Vala only: foo.clicked.connect (...). In GJS and Python the same shape
    # is `this.style_manager.connect("notify::dark")`, where the middle token
    # is a property, not a signal - applying this rule there invents signals.
    case "$f" in *.vala)
      grep -ohE '\.[a-z][a-z0-9_]*\.connect *\(' "$f" 2>/dev/null \
        | sed -E 's/^\.//; s/\.connect *\($//' ;;
    esac
    # connect("clicked", ...) / connect_after('clicked'). The leading
    # [^_a-z] guard keeps Ruby's signal_connect out, which the rule below
    # already handles - without it every Ruby signal is counted twice.
    grep -ohE "(^|[^_a-z])connect(_after|_object)? *\( *[\"'][^\"']+" "$f" 2>/dev/null \
      | sed -E "s/.*[\"']//"
    # Ruby: signal_connect("notify::position") - the detail is part of the
    # signal, so ':' stays inside the character class.
    grep -ohE "signal_connect(_after)? *\(? *[:\"'][A-Za-z0-9_:.-]+" "$f" 2>/dev/null \
      | sed -E "s/.*signal_connect(_after)? *\(? *[:\"']//"
    # gtk-rs: b.connect_clicked(...), connect_notify_local(Some("position"), ..)
    grep -ohE 'connect_notify(_local)? *\( *Some\( *"[^"]+"' "$f" 2>/dev/null \
      | sed 's/^[^"]*"//; s/"$//; s/^/notify::/'
    grep -ohE '\bconnect_[a-z0-9_]+ *\(' "$f" 2>/dev/null \
      | grep -vE 'connect_(notify|after|object)\b' | sed -E 's/^connect_//; s/ *\($//'
    # C: g_signal_connect (obj, "clicked", ...) - the name is very often on
    # the continuation line, so track the open paren rather than the line.
    awk '/g_signal_connect[a-z_]*[[:space:]]*\(/ { s = 1 }
         s { if (match($0, /"[a-z][a-z0-9_:.-]*"/)) {
               print substr($0, RSTART + 1, RLENGTH - 2); s = 0
             } else if (/\);/) s = 0 }' "$f" 2>/dev/null

    # Blueprint: clicked => $on_clicked()
    grep -ohE '^[[:space:]]*[a-z][a-z0-9_-]* *=> *\$' "$f" 2>/dev/null | sed 's/ *=>.*//'
  } | sed 's/_/-/g' | tally "$rel" signal

  # --- actions -------------------------------------------------------------
  # Prefixed names in quotes (source) or in GtkBuilder element text
  # (<property name="action-name">win.next-page</property>), plus the bare
  # names registered at an install site - a port commonly builds 'start-tour'
  # and lets the widget supply the `win.` prefix, so the literal never appears.
  {
    # Any prefix, not just app./win. - a widget action group can be called
    # anything, and kgx uses term., tab. and spad. for most of its actions.
    # Matched only in an action CONTEXT: a bare prefixed literal anywhere is
    # just as often a filename (`addp-hunk-edit.diff`, `gschemas.compiled`),
    # and no extension blocklist is ever complete.
    grep -ohE "(action[_-]?name|activate_action|accels_for_action|install_action|add_action|SimpleAction|action_target|action:|\baction\b)[^;]*['\"][a-z][a-z0-9-]*\.[a-z0-9_-]+['\"]" "$f" 2>/dev/null \
      | grep -ohE "['\"][a-z][a-z0-9-]*\.[a-z0-9_-]+['\"]" | tr -d "\"'"
    grep -ohE '<property +name="action-name"[^>]*>[^<]+' "$f" 2>/dev/null | sed 's/.*>//'
    # GJS: new Gio.SimpleAction({ name: "cancel" }) - the name is a property
    # on the next line, so track the open paren.
    awk '/new +G(io|object)?\.SimpleAction *\(|Gio\.SimpleAction\.new *\(/ { s = 1 }
         s { if (match($0, /name: *["'"'"'][^"'"'"']+/)) {
               v = substr($0, RSTART, RLENGTH); sub(/name: *["'"'"']/, "", v)
               print v; s = 0
             } else if (/\);/) s = 0 }' "$f" 2>/dev/null

    # Bare names at an install site: the widget supplies the prefix.
    grep -ohE '(SimpleAction\.new|install_action|add_action|create_action|lookup_action|action_name) *[(=:][^)]*["'"'"'][A-Za-z0-9_.-]+' \
      "$f" 2>/dev/null | sed -E 's/.*["'"'"']//'
  } | awk -F. 'NF <= 2' | grep -vE '^(org|com|io|net|www)\.' | tally "$rel" action

  :
done; } | classify
:
