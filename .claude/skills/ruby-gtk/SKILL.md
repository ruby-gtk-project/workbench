---
name: ruby-gtk
description: Build, review, refactor, or plan Ruby GTK4 and Libadwaita desktop applications using the declarative memoized-widget pattern. Use this skill whenever the user mentions Ruby + GTK, gtk4 gem, ruby-gnome, Adwaita/Libadwaita in Ruby, GNOME apps in Ruby, ListView/ListBox/SignalListItemFactory in Ruby, or asks to write, port, audit, or extend any GTK widget code in Ruby — even for small snippets or single widgets. Also use it when reviewing existing Ruby GTK code against the house style, or when planning a Ruby port of an existing GTK app (Vala/C/Python). The Ruby GTK bindings have quirks (especially Adwaita) that make from-memory code unreliable; always consult this skill first.
---

# Ruby GTK4 Declarative Patterns

House style for Ruby GTK4/Adwaita apps: every widget is a memoized method, all configuration lives in `tap` blocks, assembly happens in a single `build` method, and the app launches with one expression. All code produced or reviewed must conform to these rules — abiding by the guide is the point.

## The Pattern in 30 Seconds

```ruby
require 'gtk4'

class MyApp
  def build
    app.tap do
      app.signal_connect('activate') do
        app.add_window(window)

        window.tap do |win|
          win.title = 'My App'
          win.set_default_size(400, 300)
          win.child = box
        end

        box.tap do |b|
          b.append(label)
          b.append(button)

          button.tap do |btn|
            btn.signal_connect('clicked') { on_click }
          end
        end

        window.present
      end
    end
  end

  def app = @app ||= Gtk::Application.new('org.example.myapp', :default_flags)
  def window = @window ||= Gtk::Window.new
  def box = @box ||= Gtk::Box.new(:vertical, 8)
  def label = @label ||= Gtk::Label.new('Hello')
  def button = @button ||= Gtk::Button.new
end

MyApp.new.build.run
```

## Non-Negotiable Rules

Every one of these is enforced. Violating any of them means the code fails review.

| # | Rule | Wrong | Right |
|---|------|-------|-------|
| 1 | Widgets are memoized methods | `@btn = Gtk::Button.new` in build | `def button = @button ||= Gtk::Button.new` |
| 2 | Styles (margins, CSS classes, alignment) live in the memoized method's `tap`, never in `build` | `build` sets `margin_top` | memoized method's tap sets `margin_top` |
| 3 | `build` contains only functional calls: `append`, `child=`, `attach`, `signal_connect`, `add_controller` | styling in build | structure + behavior only |
| 4 | Appends happen **inside** the parent's `tap` block | `box.append(x)` then `box.tap` | `box.tap { \|b\| b.append(x) }` |
| 5 | Memoized methods with no styling stay on **one line** | multi-line for a bare `Gtk::Frame.new` | `def frame = @frame \|\|= Gtk::Frame.new` |
| 6 | No `return` statements — use `.then { \|x\| if x ... }` | `return unless contact` | `selected.then { \|c\| if c ... }` |
| 7 | No local variables for object config — use `tap` | `editor = Editor.new; editor.build` | `Editor.new(...).tap { \|e\| e.build }` |
| 8 | Chain multi-step operations into one expression | two statements | `@store.select(@store.add(**data))` |
| 9 | Nest child configuration inside the parent's `tap` (build reads as the widget tree) | flat sibling taps | nested taps mirroring hierarchy |
| 10 | Data models start as simple string attributes | arrays of value objects up front | `attr_accessor :name, :email` |
| 11 | Show all fields unconditionally — never toggle `visible` on empty data | `row.visible = !email.empty?` | always set the label |
| 12 | Never remove working functionality when adding features | rewrite-and-break | add one field/feature, test, repeat |
| 13 | Entry point is one expression | manual setup script | `MyApp.new.build.run` |

## Ruby Binding Quirks (Cannot Be Guessed)

The Ruby bindings differ from C/Vala docs. Before writing any Adwaita code, read `references/adwaita-quirks.md`. The critical ones:

- Namespace is `Adwaita::`, **not** `Adw::`.
- `Adwaita::Application` and `Adwaita::ApplicationWindow` are **broken** in the Ruby bindings. Use `Gtk::Application` + `Gtk::ApplicationWindow`; all other Adwaita widgets work inside them.
- `Adwaita::NavigationPage.new(child, title)` — positional args only; keyword args and no-arg-then-setters both fail. Child must exist before the page.
- `Adwaita::Avatar.new(size, text, show_initials)` and `Adwaita::Toast.new(message)` — positional args.
- When a constructor fails: try no-args, then positional args in the order the error message shows. Document new findings in the quirks reference.

## Workflow

**Writing a new app** (or porting an existing one):
1. Read `references/planning-methodology.md`. Analyze before coding; identify what's over-engineered in the source (chunk systems, async operation classes, aggregators) and drop it.
2. Build display-only first, then persistence, then C/U/D one operation at a time, verifying each checkpoint.
3. If using Adwaita widgets, read `references/adwaita-quirks.md` first.
4. Verify each checkpoint by running the app, not by reading it - use the companion `ruby-gtk-testing` skill, which drives the UI headlessly and takes screenshots. A syntax check proves nothing about a widget tree.

**Writing any widget code**: consult `references/declarative-patterns.md` for the widget's pattern (signals, factories, drawing, menus, dropdowns, gestures) and copy the shape from a real example in `references/examples/` rather than inventing.

**Checking that it works**: load the `ruby-gtk-testing` skill and drive the app. Widget wiring, dialogs and GAction state all fail silently in ways that `ruby -c` and a successful `require` will not show.

**Reviewing code against the guide**: check every rule in the table above, in order, citing rule numbers. Then check `references/style-rules.md` for the full rationale and edge cases of each rule.

**Class extraction**: when a component exceeds ~10 widget methods, has a clear logical grouping, or is reusable — extract a class with the same shape: constructor taking callbacks, `build` returning the root widget, optional `update(data)`, memoized widget methods at the bottom. See `MessageRow` in `references/examples/list_box_complex.rb` for a real multi-class example.

## Reference Files

| File | Read when |
|------|-----------|
| `references/declarative-patterns.md` | Writing any widget code — full pattern catalog: signals, list factories, Cairo drawing, menus, size groups, revealers, quick-reference tables |
| `references/style-rules.md` | Reviewing/refactoring — the 17 numbered rules with wrong/right pairs and rationale |
| `references/planning-methodology.md` | Starting a new app or porting an existing one — analysis phases, MVP sequencing, pitfalls, GNOME Contacts case study |
| `references/adwaita-quirks.md` | Any `Adwaita::` widget — constructor signatures, broken widgets, working app skeleton |
| `references/examples/*.rb` | Need a working reference implementation (see below) |

## Real Working Examples

Sourced from github.com/ruby-gtk-project/gtk-demos-and-examples (branch `ruby`) and brought into full conformance with the rules in `references/style-rules.md` (the upstream originals predate the additions guide and contain violations — styles in build, guard returns, local variables, data-driven visibility). These copies are the authoritative style reference; when upstream and these copies disagree, these copies win.

| Example | Demonstrates |
|---------|--------------|
| `header_bar.rb` | Minimal app, HeaderBar, pack_start/pack_end, linked buttons |
| `stack.rb` | Stack + StackSwitcher, add_titled/add_named, page icons |
| `stack_sidebar.rb` | StackSidebar, `.then` pattern in build, ApplicationWindow |
| `assistant.rb` | Multi-page Gtk::Assistant, page completion gating, GLib::Timeout progress |
| `clipboard.rb` | Multi-class app, Gdk clipboard, Stack-switched panels, callback injection |
| `list_box_controls.rb` | ListBox with control rows, SizeGroup across classes, attr_reader exposure, row-activated toggling |
| `list_box_complex.rb` | Extracted row class, instance-tracking hash, sort_func, Revealer expand, state-flags hover, Pango attrs, Gio::Menu |
| `file_browser.rb` | GridView + DirectoryList, SingleSelection, multiple SignalListItemFactory views, toggle-button view switcher |

When asked "how do I do X in Ruby GTK", find the closest example, show its actual code, and adapt — never fabricate API calls the bindings may not have.
