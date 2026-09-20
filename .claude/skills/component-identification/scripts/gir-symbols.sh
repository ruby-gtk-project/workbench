#!/usr/bin/env bash
# Build the authoritative GTK symbol table from GObject-Introspection (.gir).
#
# Output: <Ns.Name>\t<kind>\t<CNamePrefix>
#   kind = widget      subclasses Gtk.Widget - a thing on screen
#          controller  subclasses Gtk.EventController or Gtk.Gesture - not a
#                      widget, but behaviour: belongs on the signal axis
#          class       a GObject that is neither - models, buffers, filters,
#                      providers, layout managers, dialogs-as-objects
#          enum        an enumeration or bitfield
#          iface       an interface
#          record      a struct
#
# Why this exists: deciding "is Adw.Easing a widget?" by hand is a strike list
# that is never finished and differs per app. The GIR knows. Gtk.Adjustment,
# Gtk.StackPage, Gtk.TextTag and Gtk.EntryBuffer are all real GTK classes that
# are NOT widgets, and no regex can tell you that.
#
# Usage: gir-symbols.sh [gir-dir ...] > symbols.tsv
#   With no argument, searches the usual locations plus the Nix store.
set -uo pipefail

dirs=("$@")
if [ ${#dirs[@]} -eq 0 ]; then
  mapfile -t dirs < <(
    for d in /usr/share/gir-1.0 /usr/local/share/gir-1.0 \
             "$HOME/.nix-profile/share/gir-1.0" /run/current-system/sw/share/gir-1.0; do
      [ -d "$d" ] && printf '%s\n' "$d"
    done
    # Nix keeps each library's .gir in its own -dev output.
    ls -d /nix/store/*-dev/share/gir-1.0 2>/dev/null | head -40
  )
fi

[ ${#dirs[@]} -gt 0 ] || { echo "no gir-1.0 directory found; pass one" >&2; exit 1; }

# Prefer the UI libraries; a full store scan would otherwise pull in hundreds.
files=$(
  for d in "${dirs[@]}"; do
    ls "$d"/{Gtk-4*,Adw-1*,Gdk-4*,Gsk-4*,Vte-*,GtkSource-*,Shumate-*,WebKit*,Panel-*}.gir 2>/dev/null
  done | sort -u
)
[ -n "$files" ] || { echo "no UI .gir files in: ${dirs[*]}" >&2; exit 1; }

python3 - $files <<'PY'
import re, sys, collections

parent = {}          # (ns, name) -> parent spec
kind   = {}          # (ns, name) -> preliminary kind
cprefix = {}

for path in sys.argv[1:]:
    try:
        x = open(path, encoding='utf-8', errors='replace').read()
    except OSError:
        continue
    m = re.search(r'<namespace[^>]*\bname="([A-Za-z0-9]+)"', x)
    if not m:
        continue
    ns = m.group(1)
    m2 = re.search(r'<namespace[^>]*\bc:identifier-prefixes="([A-Za-z0-9,]+)"', x)
    cprefix[ns] = m2.group(1).split(',')[0] if m2 else ns

    for tag, k in (('class', 'class'), ('interface', 'iface'), ('record', 'record'),
                   ('enumeration', 'enum'), ('bitfield', 'enum')):
        for mm in re.finditer(r'<%s\s+([^>]*?)>' % tag, x, re.S):
            attrs = mm.group(1)
            nm = re.search(r'\bname="([A-Za-z0-9_]+)"', attrs)
            if not nm:
                continue
            key = (ns, nm.group(1))
            kind.setdefault(key, k)
            if tag == 'class':
                pp = re.search(r'\bparent="([A-Za-z0-9_.]+)"', attrs)
                parent[key] = pp.group(1) if pp else None

def resolve(key):
    """Walk the parent chain; returns the set of ancestor names seen."""
    seen, cur, guard = set(), key, 0
    while cur and guard < 64:
        guard += 1
        p = parent.get(cur)
        if not p:
            return seen
        pns, pname = (p.split('.', 1) if '.' in p else (cur[0], p))
        seen.add(pname)
        cur = (pns, pname)
    return seen

out = []
for key, k in sorted(kind.items()):
    ns, name = key
    if k == 'class':
        anc = resolve(key)
        if name == 'Widget' or 'Widget' in anc:
            k = 'widget'
        elif name in ('EventController', 'Gesture') or anc & {'EventController', 'Gesture'}:
            k = 'controller'
    out.append('%s.%s\t%s\t%s' % (ns, name, k, cprefix.get(ns, ns)))

print('\n'.join(out))
PY
