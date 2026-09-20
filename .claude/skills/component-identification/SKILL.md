---
name: component-identification
description: Enumerate the UI components of a GTK app - every widget, the CSS classes on it, the signals it responds to and the actions it installs - as an inventory another step can compare. Use when porting a GNOME app to Ruby GTK4 and needing to know what UI actually exists, when asked "what widgets does this app have" / "what's in this view" / to list or inventory an app's UI, before planning a port unit, or as the first half of a component-parity check. Works on either side: the original (Vala, C, Python, GJS, Rust, .ui, blueprint) or the Ruby port.
---

# Component identification

## What a component is

**A component is one widget in the app's widget tree, taken together with
everything that makes it that widget rather than a generic one:**

| Facet | What it is | Why it is part of the component |
|---|---|---|
| **Type** | `Adw.ActionRow`, `Gtk.ListBox` | What it is |
| **CSS classes** | `flat`, `suggested-action`, `card` | What it looks like. A `Gtk.Button` and a `Gtk.Button.destructive-action` are not the same control to a user |
| **Signals** | `clicked`, `row-activated`, `notify::selected` | What it does when touched. A button connected to nothing is a decoration |
| **Actions** | `win.new-task` it installs or targets | What command it fires |
| **Owner** | the class/file that builds it | Where it lives in the app |

Identify all five or you have not identified the component. A port that
reproduces the types and drops the CSS classes has produced a grey copy of the
app; one that reproduces types and CSS and drops the signal connections has
produced a screenshot.

**Type alone is not identity.** An app with nine `Gtk.Button`s has nine
components, and telling them apart is the whole job — they differ by their CSS
classes, their signals, and the file they live in.

## The unit the two sides can be joined on: the file

grep cannot reconstruct a widget tree, and a running app's tree cannot be
compared against source. So the inventory is **per file**, with counts.

This roughly matches how both sides are written — the Ruby house style (see the
`ruby-gtk` skill) puts one component class per file with its widgets as
memoized methods — but **do not assume one file is one component.** Upstream
very often splits a single component across two files:

| Upstream | | |
|---|---|---|
| `src/widgets/paginator.rs` | the subclass, the `#[template_child]`s, the callbacks | gtk-rs |
| `data/resources/ui/paginator.ui` | the widget tree, the CSS classes, the signals | GtkBuilder |
| → `lib/app/paginator.rb` | both halves, in the port | Ruby |

The same holds for a `.py` class beside its `.blp`, or a `.vala` class beside
its `.ui`. **The component is the set of files, not the file.** Scan per file,
then union the rows of every upstream file that maps to the same port file
before comparing anything — otherwise the widget tree is on one side of the
join and the callbacks on the other, and both look half-missing.

Multiplicity lives in the counts: three `Adw.ActionRow`s in a file is
`widget  Adw.ActionRow  3`, and a port with two has a gap of one.

## How to identify

### Step 1 — Find the declarative UI first

**Before scanning anything, look for `.blp` and `.ui` files.** Where they
exist they *are* the component inventory, and they are a far better starting
point than any grep over source:

```sh
find <tree> \( -name '*.blp' -o -name '*.ui' \) -not -path '*/.git/*' | sort
```

A declarative file gives you, in one place and already correct, what the scan
can only approximate from source:

| | Why it beats scanning source |
|---|---|
| **The tree** | Nesting is literal. You can see that this `Gtk.Box` is inside that `Adw.ToolbarView`, which no flat TSV will tell you |
| **Counts** | Each `<object>` / `Foo {` is one real widget. No factory methods, no loops, no guessing |
| **CSS classes** | `<style><class name="flat"/></style>` and `styles ["flat"]` sit on the widget they belong to |
| **Signals** | `<signal name="clicked" handler="on_clicked"/>` and `clicked => $on_clicked()` name the handler too |
| **Boundaries** | One `<template class="...">` or `template $Foo:` is one component — this is your unit list, for free |

So read them first, and let the result tell you how much work is left:

```sh
# the component map: every template root, i.e. every unit
grep -l '<template\|^template ' $(find <tree> -name '*.ui' -o -name '*.blp')
grep -hE '<template class="[^"]+" parent="[^"]+"|^template +\$?[A-Za-z]+ *:' \
  $(find <tree> -name '*.ui' -o -name '*.blp')
```

**Not every declarative root is a `template`.** GJS/blueprint apps commonly
declare a **top-level named object** instead, loaded by a builder helper and
destructured by id — `Adw.ApplicationWindow window { }` at column 0. On
Commit's upstream, four of five units are written that way and only one uses
`template`, so matching templates alone finds 20% of the app:

```sh
grep -hE '^[A-Z][A-Za-z0-9.]* +[a-z_][A-Za-z0-9_]* *\{' <blp files>   # named roots
```

Cross-check the unit list against the source files that `import`/`include` each
`.blp` or `.ui`.

**What this does not cover, and when to skip it.** A declarative file shows
what is built at startup; it cannot show widgets added at runtime, conditional
branches, or anything the source builds directly. And some upstreams have no
declarative UI at all — gtk-rs apps often build in code, and the Ruby port
*never* has `.ui` files by design (the house style builds widgets as memoized
methods). So:

- **Upstream with `.blp`/`.ui`** — read those first, then scan the source for what they don't cover.
- **Upstream without them** (or the port side, always) — go straight to the scan.

Either way the scan is still run on both sides, because the comparison in
`component-parity` needs the same TSV shape from each.

### Step 2 — Build the symbol table, then scan

Deciding whether `Adw.Easing` is a widget is not a judgement call — GTK already
declares the answer. Build the table once from GObject-Introspection and the
scan classifies against it:

```sh
scripts/gir-symbols.sh > scripts/symbols.tsv    # once per machine
scripts/component-scan.sh <tree> > components.tsv
```

`gir-symbols.sh` reads the `.gir` XML that ships with GTK, libadwaita, VTE,
GtkSourceView and friends, walks each class's parent chain, and writes
`Ns.Name<TAB>kind`:

| kind | Means | Examples |
|---|---|---|
| `widget` | subclasses `Gtk.Widget` — a thing on screen | `Gtk.Button`, `Adw.ActionRow` |
| `controller` | subclasses `Gtk.EventController`/`Gtk.Gesture` | `Gtk.GestureClick`, `Gtk.EventControllerKey` |
| `type` | a real GTK class that is **not** a widget | `Gtk.Adjustment`, `Gtk.StackPage`, `Gtk.TextTag`, `Gtk.EntryBuffer` |
| `enum` / `record` / `iface` | not objects at all | `Gtk.Orientation`, `Adw.Easing` |

This is the authority. A hand-kept strike list never finishes and differs per
app; `Gtk.Adjustment`, `Gtk.StackPage` and `Gtk.TextTag` are all genuine GTK
classes that no regex can distinguish from `Gtk.Button`.

**Build it in an environment that has the app's own dependencies** — the port's
`nix develop` shell, or after installing its `-dev` packages. A library whose
`.gir` is absent produces no rows, and its types stay classified `widget`
conservatively; that is how `GtkSource.Buffer` ends up in the widget stream on
a machine without GtkSourceView installed.

Without a symbol table the scan still runs, everything matched stays `widget`,
and you strike by reading — see the fallback table in Step 3.

### Step 3 — Scan

```sh
scripts/component-scan.sh <tree> > components.tsv
```

One row per distinct item per file:

```
<file>	<kind>	<value>	<count>
core/Widgets/ItemRow.vala	widget	Adw.ActionRow	3
core/Widgets/ItemRow.vala	css	priority-1	1
core/Widgets/ItemRow.vala	signal	row-activated	1
```

`kind` is `widget`, `css`, `signal` or `action`. Paths are relative to the
tree, so two scans diff directly. `Adwaita::ActionRow` (Ruby),
`Adw.ActionRow` (Vala/blueprint) and `class="AdwActionRow"` (GtkBuilder) all
normalise to `Adw.ActionRow`.

### Step 4 — Read the files

The scan is a lead, not a verdict. It matches text, so it over-reports and
under-reports in known ways, and every one of them needs a human decision:

**Over-reports.** Plenty of namespaced names are not widgets — on a
GtkBuilder-heavy tree, around a third of what the regexes match. **With a
symbol table this is already done for you**: those rows arrive as kind `type`,
`controller`, `enum` or `record` and never reach the widget count. What
follows is the fallback for when no symbol table could be built, and a
description of what the classifier is doing:

| Strike | Examples |
|---|---|
| Enums and flags | `Adw.Easing`, `Adw.DialogPresentationMode`, `Gtk.Orientation` |
| `<child>` wrappers | `Gtk.StackPage`, `Adw.TabPage`, `Gtk.ListItem` |
| Models and buffers | `Gtk.EntryBuffer`, `Gtk.TextBuffer`, `*Filter`, `*ListModel`, `*Selection`, `Gtk.Adjustment` |
| Layout managers | `Gtk.BoxLayout`, `Adw.ClampLayout` |
| Singletons and helpers | `Adw.StyleManager`, `Gtk.Builder`, `Adw.TimedAnimation`, `Adw.CallbackAnimationTarget` |
| Tags, providers and themes | `Gtk.TextTag`, `Gtk.CssProvider`, `Gtk.StyleProvider`, `Gtk.StyleContext`, `Gtk.IconTheme` |

**Event controllers and gestures are the exception** — `Gtk.EventControllerKey`,
`Gtk.GestureClick`, `Gtk.ShortcutController` are not widgets, but they *are*
behaviour, and dropping them loses a whole class of interaction. The classifier
gives them their own `controller` kind for this reason: compare them on the
signal axis of the widget they are attached to, never in the widget count.

**A symbol the table does not know stays `widget`.** That is deliberate — an
unknown name is more likely an app's own widget class than a mistake — but it
means an unclassified row is a row you still have to read.

`Gtk.Template`, `Gtk.Template.Child` and `Gtk.Template.Callback` are PyGObject
template plumbing and are filtered by the script, but the widgets they stand
for are real — their types are in the `.blp`/`.ui`, not in the Python.
`Adw.CallbackAnimationTarget` and `Adw.TimedAnimation` are real objects but not
widgets, so they belong under behaviour, not in the widget count.

**Under-reports.** These are the ones that matter, and only reading finds them:

- **Widgets built in a loop.** `foreach (var p in projects) list.append (new ProjectRow (p))` is one scan row and N components on screen. Record it as a *repeater*: one component, variable count, driven by that collection.
- **Widgets built conditionally.** A row added only when a setting is on is a component that exists in a state the scan sees as unconditional.
- **CSS classes set dynamically.** `add_css_class (priority_class ())` attaches a class the scan cannot name. Follow the expression and list every class it can produce.
- **CSS classes from the stylesheet side.** The app's `.css` files define classes the source may apply indirectly. Read them; a class defined and never applied is dead, and a class applied and never defined is a bug worth reporting either way.
- **Composite widgets.** A project's own `ItemRow` is a component whose parts are in another file. The inventory records the use *and* follows into the definition.
- **Bare blueprint declarations.** `ActionRow { }` without its `Adw.` prefix inside a `.blp` is not matched.
- **CSS classes behind a C macro.** `gtk_widget_add_css_class (w, KGX_WINDOW_STYLE_ROOT)` names nothing readable. The script resolves `#define NAME "value"` across the tree, including from `.h` files — but only single-token literal defines. A class assembled at runtime (`g_strdup_printf`) still needs reading.
- **Widgets from a submodule or a vendored library.** Read `.gitmodules` and every `import ... from '../<submodule>/...'`. Commit's `ThemeSelector` — three `Gtk.CheckButton`s, an action and 52 lines of CSS — lives in the `troll/` submodule, so it produces no upstream rows at all, and the port's faithful copy then reads as an unexplained extra plus a stylesheet gap. If the submodule is not checked out the scan cannot see it; scan it separately and union its rows into the importing file's.
- **Menu models.** A blueprint `menu app-menu { section { item { ... } } }` or a GtkBuilder `<menu>` is all lowercase keywords, so it produces nothing. Count the `item` entries, and record every `custom:` slot as a component boundary — it hosts a widget built in source.
- **Widgets from libraries other than GTK and libadwaita.** The scan knows `Vte`, `GtkSource`, `Shumate`, `WebKit` and `Panel` as well as `Gtk`/`Adw`, but an app embedding anything else — a map view, a chart widget, a custom C library — produces no row for it. Read the `.ui` `parent=` attributes and the build file's dependencies to find out which libraries are in play before trusting the widget stream.
- **App-defined widgets used as parents.** `<template class="KgxSimpleTab" parent="KgxTab">` means this app subclasses its own widget. Neither name is a GTK type, so neither is a row — but the inheritance is real and the port has to reproduce it. Template roots whose `parent=` is an app class are a component hierarchy; map it before comparing anything.
- **App-defined template classes.** `<template class="PaginatorWidget" parent="AdwBin">` gives a row for `Adw.Bin` and none for `PaginatorWidget`, because it is this app's own name, not a GTK type. Every `<child>` that instantiates it is a component whose parts are in the file that defines the template — resolve it, and count the uses.
- **Widgets from a shared factory.** A private `build_button` called from three memoized methods is one textual occurrence and three widgets on screen. Count the *call sites*, not the constructor. This is the most common way a correct port reads as a gap of two.
- **Actions whose name is never a literal.** A port that builds `Gio::SimpleAction.new(name)` from a loop over `{'start-tour' => ..., 'next-page' => ...}` installs four actions and puts none of them in the scan, because the prefix (`win.`) is supplied by the widget and the name is a variable. Open every `add_action` / `install_action` / `SimpleAction.new` site and read the names off it. The scan's `action` stream is the least trustworthy of the four for exactly this reason.
- **Signals connected in a loop or a helper.** Same shape as the factory case: one `connect` in a helper called per row is one row in the scan and N live connections.

### Step 5 — Write the inventory

One `## <file>` section per component file, in the order a user meets them
(window, then its pages, then its dialogs — not alphabetical):

```markdown
## core/Widgets/ItemRow.vala — one task row in a list

| Widget | × | CSS | Signals | Notes |
|---|---:|---|---|---|
| `Adw.ActionRow` | 1 | `item-row`, `priority-{1..4}` (dynamic) | `activated` | priority class recomputed on `notify::priority` |
| `Gtk.CheckButton` | 1 | `circular-check` | `toggled` | completes the task |
| `Gtk.Label` | 2 | `dim-label` (2nd only) | — | content, due date |
| `Gtk.Revealer` | 1 | — | — | holds the detail pane |

Repeaters: none. Conditional: the due-date label only when `item.due != null`.
```

Say what the component *is* in the heading. "one task row in a list" is what
makes the inventory readable a month later; the file path alone is not.

## Scope it

A whole-app inventory of a large GNOME app is thousands of rows and nobody
reads it. Identify components **one unit at a time** — one window, one dialog,
one page, as `PLAN.md` defines a unit — and the inventory stays the size of
the thing being ported.

Absent a `PLAN.md` (see below), take a unit to be **one top-level widget class**
— one `.ui`/`.blp` template, one `impl ObjectSubclass` block, one `GtkWidget`
subclass, one `G_DEFINE_TYPE` / `G_DECLARE_FINAL_TYPE` pair in C — together
with the source file that backs it and the port file that corresponds to it. Two additions, without which real parts of the app belong to
no unit at all:

- **One unit for the application class.** `BinaryApplication(Adw.Application)` is not a widget class, but it holds the actions, the accelerators, the About dialog and the preferences entry point.
- **One unit per standalone `.blp`/`.ui` object with no backing source file** — a shortcuts window or a menu definition is a component that no widget subclass owns.

The exception is the opening survey of a fresh fork, where the totals are the
point:

> planify upstream: 1730 widget rows across its source, 144 distinct types, 99
> distinct CSS classes, 195 distinct signals. The `ruby` branch: 325 rows, 81
> types, 33 CSS classes, 29 signals.

That is a map of how much app is left, not an inventory. Do not try to act on
it directly; pick a unit.

## Rules

- Never list a widget type without its CSS classes and signals. A bare type
  list is the inventory that makes a port look finished when it is not.
- Never strike a scan row as "not a widget" without opening the file.
- A dynamic CSS class is listed with every value it can take, not as `dynamic`.
- When a widget's signal handler is the only thing it does, name the handler.
  A component's behaviour is part of its identity.
