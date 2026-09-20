---
name: component-parity
description: Prove that a Ruby GTK4 port's UI matches the app it was ported from - the same widgets in the same numbers, carrying the same CSS classes, responding to the same signals and actions, and saying the same translatable strings. Use when asked whether a port's UI is complete / matches / "looks the same" / "has component parity", when reviewing a port PR that adds UI, when a ported view looks or behaves subtly wrong, when a ported view's labels were retyped or reworded, or before calling a port unit or a whole port finished. Pairs with test-parity and translation-parity; all are required before a port is done.
---

# Component parity

## What component parity means

**A port has component parity when, for every component the original builds,
the port builds one that is the same on all four axes: the same widget type in
the same number, carrying the same CSS classes, responding to the same signals
and actions, and showing the same translatable strings.**

Four axes, and **all four must hold for the same component**:

1. **Count.** The original's file builds three `Adw.ActionRow`s; the port's
   corresponding file builds three. Not two, not four. Widget-by-widget, not
   an app-wide total — an app-wide total can balance a missing dialog against
   an invented one and report parity.
2. **Style.** Each of those rows carries the same CSS classes as its original,
   including the classes applied conditionally at runtime, and the classes
   themselves are defined in the port's stylesheet with the same rules. A
   `Gtk.Button` with `destructive-action` dropped is the wrong button, not a
   styling nit — it is the red Delete that came out grey.
3. **Behaviour.** Each responds to exactly the same signals and fires the same
   actions. Not "has a handler" — the same signal set. A row that upstream
   connects to both `activated` and a long-press gesture, and the port connects
   only to `activated`, is a component with a feature missing, and no screenshot
   will ever show it.
4. **Text.** Every user-visible string this component shows goes through a
   translation marker, and its msgid is byte-identical to the one upstream's
   component used. A label the port retyped, reworded or left unmarked is a
   label that has no translation in any language upstream ships, and an English
   screenshot of it looks perfect.

### Why all four, and why per component

Each axis alone fails in a way that looks like success:

| Axis alone | What passes that shouldn't |
|---|---|
| Count only | A grey, inert copy of the app with every widget in place |
| Style only | A pixel-perfect app where nothing responds to clicks |
| Behaviour only | A working app that looks nothing like the original |
| The first three | A perfect app that speaks only English, in a project that ships 78 languages |

And per-component rather than per-app, because parity is a claim about
*correspondence*. Totals cannot distinguish "ported the preferences dialog" from
"ported forty buttons scattered anywhere".

### Nothing authorises a skip

A component, a CSS class, a signal or an action either has a counterpart in the
port — which you **name and locate** — or it is a gap. No document creates a
third option. The port's own `PORTING.md` is useful for *navigation* (its
architecture table is the file mapping) and carries no authority over scope:
it is written by the port, about the port, and citing it to excuse the port's
own missing work is circular.

"C-specific plumbing", "not applicable", "does not carry over" and "the
bindings do not support it" are all gaps. A binding limitation is a reason a
gap is hard — record it in `FINDINGS.md` and leave the row a gap.

What follows is different: these are the same thing spelled differently, and
each one still requires you to say **where** you found it.

### What is not a parity failure

Ruby bindings rename things, and the port is not obliged to mirror the
original's file layout or class names. These are **correspondences**, resolved
by naming where the thing lives, not gaps:

- `AdwAboutDialog` → `Adwaita::AboutDialog`; `Adw.` and `Adwaita::` are the
  same namespace.
- A `.ui` file's widget tree built in Ruby as memoized methods (the house style
  — see the `ruby-gtk` skill). The port has no `.ui` files, by design.
- One upstream file split across two Ruby files, or merged. The ledger maps
  file to file(s); the axes are then compared over the mapped set.
- A widget replaced by a strictly newer equivalent, where upstream itself is
  behind — `Gtk.Spinner` → `Adw.Spinner`. Record the substitution and the
  reason. Do not make this judgement silently.

A correspondence that is asserted but not located is a gap. "Probably built
somewhere" is not a finding, and neither is "the port does this differently"
without naming the file and line where it does it.

## How to prove it

### Step 1 — Inventory both sides

Use the `component-identification` skill on the upstream tree and on the port's
`ruby` branch, scoped to the same unit. **Start with its Step 1**, and run it on **both** trees: find the `.blp`/`.ui`
files before anything else. Upstream's `<template>` roots are the unit list and
the file mapping of Step 2 below, handed to you for free. The port *usually*
has none — the house style builds widgets as memoized methods — but a bindings
gap can force one: Commit-rb keeps `shortcuts-window.ui` and
`theme-selector.ui` because `GtkShortcutsWindow` cannot be constructed from
Ruby. Do not assume the port side is empty; look. Both trees live in the same fork — the
original on its branch, the port on `ruby`:

```sh
# The fork's upstream branch is whatever the parent's default branch is -
# it is not always `main`, and these forks carry release branches too.
REPO=$(basename -s .git "$(git remote get-url origin)")   # e.g. binary-rb, not binary
UP=$(gh api "repos/ruby-gtk-project/$REPO" --jq '.parent.default_branch')

# The `ruby` branch is an ORPHAN branch - it shares no history with upstream,
# so `git merge-base` returns nothing. There is no commit to derive; the
# upstream sha has to be recorded rather than computed. Take it from the
# port's PORTING.md / ledger header if it is written down there, and otherwise
# use the tip and WRITE IT INTO the ledger, so the next review compares
# against the same commit instead of a moving target.
BASE=origin/$UP   # or the sha the ledger already pins

git worktree add --detach ../upstream "$BASE"
git worktree add --detach ../port     origin/ruby
component-scan.sh ../upstream > up.tsv
component-scan.sh ../port     > port.tsv
```

Do the reading step on both sides. A port inventory built only from the scan
will report every memoized widget method correctly and every loop-built widget
wrongly, which is precisely where ports go thin.

### Step 2 — Map file to file

Before comparing anything, write the file mapping for the unit:

```
src/widgets/paginator.rs + data/resources/ui/paginator.ui -> lib/app/paginator.rb
core/Widgets/ItemRow.vala                                 -> lib/app/widgets/item_row.rb
src/Dialogs/Preferences/*.vala                            -> lib/app/dialogs/preferences.rb
```

**The mapping is many-to-many, and usually 2→1.** Upstream splits a component
across its source file and its `.ui`/`.blp` template; the port merges both into
one Ruby file. So before joining anything, *union the rows of every upstream
file on the left of an arrow*:

```sh
union() {   # union <tsv> <anchored ERE over paths>
  awk -F'\t' -v u="$2" '$1 ~ "^(" u ")$" {k[$2 FS $3] += $4}
                         END {for (x in k) print x FS k[x]}' "$1" | sort
}
union up.tsv   'src/window\\.py|src/window\\.blp'
union port.tsv 'lib/window\\.rb|lib/conversion_row\\.rb'
```

The second argument is an **ERE, not a path list**, and it reaches awk as a
*string* — so a dot needs `\\.`, two backslashes. With one (`\.`) awk prints
`warning: escape sequence '\.' treated as plain '.'` and matches any character,
which is how `src/a\.c` silently also folds in `src/abc`.

Union **both** sides — the mapping is often 2→2, not 2→1, because the port
factors a block that upstream repeats inline into its own file.

Two corrections to make by hand before you trust the union:

- **The template root is one widget counted twice.** `class BinaryWindow(Adw.ApplicationWindow)` in the source and `template $BinaryWindow: Adw.ApplicationWindow` in the `.blp` are the same window. Summing gives 2 against the port's 1. Strike the source-file row for the parent type before unioning.
- **A port file with no upstream file opposite it** is either a factored-out repeat — name the upstream block it came from — or an unexplained extra. It is not automatically a gap in either direction.

Joining file-to-file instead of unioning puts the widget tree on one side and
the callbacks on the other, and reports both halves as missing.

An upstream file with no port file opposite it is the first and largest kind of
gap, and it is found here rather than in any diff.

### Step 3 — Compare on each axis

Per mapped file, per widget:

```sh
# the shape of the comparison, per file and kind
join -t$'\t' -j1 -a1 -a2 \
  <(awk -F'\t' '$1==U && $2=="widget"{print $3"\t"$4}' up.tsv   | sort) \
  <(awk -F'\t' '$1==P && $2=="widget"{print $3"\t"$4}' port.tsv | sort)
```

Read the result as three questions, in this order:

- **Missing** — in upstream, not in the port. A gap unless located elsewhere.
- **Different count** — present on both, different numbers. Usually a repeater
  built for one item instead of a collection, or a conditional branch not
  ported.
- **Extra** — in the port, not upstream. Not automatically a failure (the house
  style may use a `Gtk.Box` where a `.ui` used a template) but every extra is
  explained, because an unexplained extra is usually a widget standing in for
  one that was not understood.

Then the same over `css`, `css-name`, `signal` and `action` — but read their
counts differently:

> **`controller` rows are compared on the signal axis, not the widget axis.**
> A `Gtk.GestureLongPress` upstream with nothing opposite it in the port is a
> missing interaction, not a missing widget. **`type` rows** (models, buffers,
> filters, adjustments) are compared as data plumbing: the port may reach the
> same behaviour with plain Ruby and no GObject model at all, which is a
> correspondence — say where the behaviour lives instead.

> **Only the `widget` stream's counts are per-instance.** A `css` or `signal`
> count is the number of *attachment sites* in the text. Upstream calling
> `add_css_class("error")` in six branches of one handler, against a port that
> factors those six branches into one helper, is `6` vs `1` with identical
> behaviour. On these two axes compare the **set**, and reconcile any count
> difference by reading rather than by reporting it.

#### The text axis

`component-scan.sh` does not carry strings, so this axis uses the census from
`translation-parity`, scoped to the two mapped files rather than to the tree:

```sh
diff <(translation-parity/scripts/msgid-census.sh "$UP_FILE"   | cut -f1,2) \
     <(translation-parity/scripts/msgid-census.sh "$PORT_FILE" | cut -f1,2)
```

Each row of the difference is one of three things, and only the first is fine:

- **Moved.** The string is in the port, in another file — a label that lived in
  the `.blp` upstream and is built in Ruby here. Locate it and say where, the
  same as a moved widget.
- **Reworded or retyped.** Same idea, different bytes: `Delete Contact` against
  `Delete contact`, or a label with the mnemonic underscore stripped. This is a
  **gap**, not a nit. A msgid is a hash key, so one changed character discards
  every language's translation of that label while the English still reads
  correctly.
- **Unmarked.** The port builds the label as a bare literal with no `_()`
  around it. Also a gap, and the one the scan finds most often, because it is
  invisible in every English screenshot.

Interpolation deserves its own mention because it is the common way to fail
this axis without noticing. `"Exported #{count} contacts"` is not a
translatable string — `#{}` runs before any marker could see it, so the lookup
key differs on every call and matches nothing in any catalogue. The port must
call `format(n_("Exported %d contact", "Exported %d contacts", n), n)` with
upstream's msgids.

**What this axis does not do:** the catalogue-level work. Whether the port
ships upstream's `po/`, under the right domain, with every language and every
msgid accounted for is `translation-parity`'s ledger, not this one. This axis
asks only whether *this component* says what its original said. A component can
pass here while the app has no `po/` directory at all — which is why both
ledgers exist, and why neither implies the other.

Two more correspondences on the `signal` axis:

- `notify::selected` in the port against a bare `notify` upstream is the port *narrowing* the connection — strictly better, not a gap. Verify the property is the one upstream's handler acted on.
- An action whose name never appears as a literal (built from a variable, or from a `create_action('quit', ...)`-style helper) will be absent or unprefixed in the stream on one side only. Read the install site before recording a gap.

### Step 4 — Confirm the styling actually renders

The CSS axis has a second half the scan cannot see: a class attached to a
widget does nothing unless the port's stylesheet defines it. For every class in
the unit, check that the rule exists in the port's CSS and says the same thing.
Diff the two stylesheets directly — they are both plain CSS, and this is the one
place where the two sides can be compared literally:

```sh
find ../upstream ../port -name '*.css' -not -path '*/.git/*'
diff <upstream.css> <port.css>
```

Locate them; do not assume a path. The stylesheet may be one file or seven, and
the port frequently relocates it (`data/resources/style.css` upstream,
`data/style.css` in the port).

**The port may have no `.css` file at all** — binary-rb keeps its stylesheet as
a Ruby heredoc loaded with `provider.load(data: STYLE)`. Find it with
`grep -rn 'CssProvider\|load(data:' <port>` and extract the heredoc to a temp
file before diffing. An empty `find` on the port side is not evidence of a
missing stylesheet.

**Variant stylesheets are a separate comparison.** Upstream shipping both
`style.css` and `style-hc.css` (high contrast) means two diffs: check the port
loads an equivalent variant and switches to it on the same condition, or record
its absence as a gap in its own right.

Ports often copy the stylesheet across verbatim — planify-rb's seven files are
byte-identical to upstream's. When it is, this half of the axis is satisfied
for free, and the whole CSS question collapses to the one the scan answers:
which of those classes does the port actually *attach* to a widget. A copied
stylesheet is not evidence of style parity; it is the reason style gaps in
these ports are attachment gaps, and it makes the `css` stream the axis to read
closely rather than the one to skip.

**Differences that are correspondences, not gaps.** The rule is that a rule
which *differs* is a gap — but judge the rendered result, not the text:

- **Asset URIs.** `url('/org/gnome/Tour/hand-fg.svg')` (a GResource path) against `url('@ASSETS@/hand-fg.svg')` (substituted at build time) is the same rule. gnome-tour-rb differs from upstream on exactly these two lines and has full style parity.
- **Build-time tokens** — `@ASSETS@`, `@datadir@`, `@APP_ID@` — resolve before the CSS is loaded. Resolve them by hand before comparing.
- **Adwaita named colours** — `@accent_bg_color` against a hex literal is a real difference: the named colour follows the user's theme and the literal does not.
- **Platform classes are not undefined.** `flat`, `circular`, `suggested-action`, `destructive-action`, `devel`, `card`, `frame`, `view`, `dim-label`, `title-1..4`, `heading`, `monospace`, `numeric`, `pill`, `osd`, `boxed-list`, `accent`/`warning`/`error`/`success` are defined by GTK and libadwaita, not by either stylesheet. Never report them as missing a rule — only app-namespaced classes need one in the port's stylesheet.
- **Element names against classes.** `gtk_widget_class_set_css_name (klass, "kgx-tab")` makes upstream's selector `kgx-tab { }` — an *element* selector. A Ruby port has no GType to hang a css name on and re-expresses these as classes: `.console-rb-tab { }`. That is a correspondence, not a gap. The scan puts them in their own `css-name` stream for exactly this reason: compare `css-name` upstream against `css` in the port, record the name→class mapping once per unit, and compare the rule bodies. Comparing the two streams directly reports every one of them twice — once missing, once extra.

Then run the port and look. Screenshot the unit with the `ruby-gtk-testing`
skill and compare against the original running. Colour, spacing and weight are
the things a class carries, and reading a class name tells you none of them.

### Step 5 — Confirm the behaviour actually fires

A connected signal is not a working signal. For each signal in the unit, drive
it with the `ruby-gtk-testing` driver — `button.activate`, `row.emit(:activated)`
— and assert the effect the original has. A handler connected to an empty
method passes every static check there is.

### Step 6 — Write the ledger

`COMPONENT_PARITY.md` at the root of the port's `ruby` branch, one section per
unit, appended to as units land:

```markdown
# Component parity — <app>

| | |
|---|---|
| Upstream | `main` @ `<sha>` |
| Port | `ruby` @ `<sha>` |
| Units with parity | 3 / 27 |

## Unit: item row  —  `core/Widgets/ItemRow.vala` -> `lib/planify/widgets/item_row.rb`

| Widget | Up × | Port × | CSS | Signals | Text | Verdict |
|---|---:|---:|---|---|:-:|---|
| `Adw.ActionRow` | 1 | 1 | ✓ `item-row`, `priority-{1..4}` | ✓ `activated` | ✓ | parity |
| `Gtk.CheckButton` | 1 | 1 | ✓ `circular-check` | ✓ `toggled` | — | parity |
| `Gtk.Label` | 2 | 1 | — | — | — | **gap**: due-date label not built |
| `Gtk.MenuButton` | 1 | 1 | ✓ `flat` | ✓ `clicked` | ✗ | **gap**: `_("_Delete")` built as bare `'Delete'` |
| `Gtk.GestureLongPress` | 1 | 0 | — | ✗ `pressed` | — | **gap**: no context menu on long press |

Stylesheet: `priority-3` defined upstream as `color: @orange_3`, port has
`color: @yellow_5`. **gap**.
Messages: 4 upstream, 3 in the port; `_Delete` unmarked, `Due %s` reworded to
`Due: %s`. **gap** — both rows are open in `TRANSLATION_PARITY.md`.
Driven: check toggles completion ✓, long press does nothing ✗.
Screenshot: `tmp/shots/item-row.png`.
```

The `Text` column is `✓` when this widget's strings are marked and
byte-identical, `✗` when one is not, and `—` when the widget shows no text of
its own. The `Messages:` line carries the counts, because a string the port
dropped entirely belongs to no widget row and would otherwise vanish.

A unit has parity when every row says `parity`, the stylesheet and messages
lines are clean, and the driven line has no ✗. One gap is not a pass with a
note.

## Worked example — planify-rb

The opening whole-app scan:

| Axis | Upstream distinct | Port distinct | In upstream, not in port |
|---|---:|---:|---:|
| Widget types | 144 | 81 | 74 |
| CSS classes | 99 | 33 | 88 |
| Signals | 195 | 29 | 175 |

The signal row is the one to read. The port has 81 of 144 widget types — it
looks more than half built — while connecting 29 of 195 signals. That is the
shape of a port with the UI laid out and the behaviour not yet wired, and it is
exactly the state that a screenshot review passes and a component-parity review
fails.

Among the 74 missing widget types, `Adw.NavigationView`, `Adw.NavigationPage`,
`Adw.BottomSheet` and `Adw.PasswordEntryRow` are whole navigation and
credential flows absent from the port. `Adw.Easing` and
`Adw.DialogPresentationMode` in the same list are enums, not widgets — strike
them, per `component-identification` Step 4.

## Rules

- Never report parity from the scan alone. Steps 4 and 5 are where the axes are
  actually checked; the scan only says where to look.
- Never compare app-wide totals and call it parity. The unit is the component.
- An extra widget in the port is explained in the ledger or removed.
- A CSS class that exists on both sides but whose rule differs is a gap, and it
  is the easiest one to miss — the class name matches.
- A label that exists on both sides but whose msgid differs is a gap for the
  same reason, and it is missed even more easily, because the English renders
  correctly and only the other languages break.
- Never fix a text-axis gap by rewording upstream's msgid to match the port.
  The port moves to upstream's bytes, never the reverse — upstream's bytes are
  the ones 78 catalogues are keyed on.
- A text-axis gap is recorded in **both** ledgers: here against the component,
  and in `TRANSLATION_PARITY.md` against the message. They are closed by one
  edit and tracked in two places, because a reader of either must be able to
  see it.
- Component parity and test parity are separate claims. Neither implies the
  other, and a port is finished only when both hold.
