# Driving Ruby GTK4 Widgets from a Test

Recipes for reaching into a running app. All of these assume the memoized-method
house style, where every widget has a method name you can call.

## Contents

1. [Windows and dialogs](#1-windows-and-dialogs)
2. [Buttons and actions](#2-buttons-and-actions)
3. [Entries and rows](#3-entries-and-rows)
4. [Lists, grids and selections](#4-lists-grids-and-selections)
5. [File dialogs](#5-file-dialogs)
6. [Async work](#6-async-work)
7. [Screenshots](#7-screenshots)
8. [Reaching an object you did not keep](#8-reaching-an-object-you-did-not-keep)

---

## 1. Windows and dialogs

`Adwaita::Dialog` presented on an `Adwaita::ApplicationWindow` lives *inside*
the window, so the window knows about it:

```ruby
window.visible_dialog          # the dialog, or nil
window.visible_dialog&.close   # dismiss whatever is open
```

Presented on a `Gtk::ApplicationWindow` it becomes a separate toplevel instead,
and `visible_dialog` returns nil. If a dialog seems to vanish, that is usually
why - check `Gtk::Window.list_toplevels.length`, and see the `ruby-gtk` skill's
`adwaita-quirks.md` on why the Adwaita window is preferred.

Dialogs stack. Close each one before opening the next, or your screenshot shows
the one underneath.

```ruby
d.step('dismiss the first-run prompt') do
  d.check('prompt appeared') { app.main_view.window.visible_dialog }
  app.main_view.window.visible_dialog&.close
end
```

Apps that present something on idle at startup need this as step one, before
anything else can be seen.

## 2. Buttons and actions

Activate the widget rather than calling your handler, so the wiring is covered:

```ruby
button.activate                    # fires 'clicked'
row.activate                       # fires 'activated'
```

For `Gio::SimpleAction`, go through the action map so the name is tested too:

```ruby
window.lookup_action('remove-pictures').activate(nil)
app.lookup_action('preferences').activate(nil)

# Parameterised actions need a GLib::Variant of the declared type.
window.lookup_action('sort-by').activate(GLib::Variant.new('by_title'))
```

### GVariants are unwrapped on the way out but not on the way in

This asymmetry is worth knowing before you write any menu-action code, because
two of its three failure modes are silent:

```ruby
action.state                  # => true          (not a GLib::Variant)
action.state.get_boolean      # NoMethodError: undefined method for true

# The activate parameter is unwrapped too:
action.signal_connect('activate') { |_, parameter| parameter }   # => "by_title", a String

# But `state=` casts to GVariant* without a type check, so it does not raise:
action.state = GLib::Variant.new(false)   # correct
action.state = 'a string'                 # warns to stderr, silently ignored
action.state = true                       # SIGSEGV - takes the process down
action.state = action.state               # SIGSEGV, from a plain round trip
```

`change_state` is the same operation done safely - it validates against the
action's declared state type and accepts plain Ruby values as well as
GVariants - so prefer it and the problem disappears:

```ruby
action.signal_connect('activate') do |_, parameter|
  action.change_state(parameter)          # safe with the unwrapped value
  config.sort_order = parameter.to_sym
end
```

`Gtk::Actionable#action_target=` has the same unchecked cast with a quieter
failure: a plain value is dropped and the target stays nil, with no warning at
all. Wrap it - `button.action_target = GLib::Variant.new('x')`.

Menu actions are therefore high-value test targets, and the failures are
spread across the whole severity range: a plain string assignment only warns, so
the app runs on with the wrong menu item ticked; `state.get_boolean` raises the
moment a toggle is used; and a plain boolean assignment segfaults. None of that
shows up in `ruby -c`, in a successful require, or in a screenshot of the window
at rest - you have to activate the action and read the state back:

```ruby
d.step('sort by title') do
  window.lookup_action('sort-by').activate(GLib::Variant.new('by_title'))
  d.check('action state followed') { window.lookup_action('sort-by').state == 'by_title' }
  d.check('model reordered')       { model.items.map(&:title) == model.items.map(&:title).sort }
end
```

Check both halves. The state and the effect are separate code paths, and this
is exactly the pair where one can work while the other quietly does not.

## 3. Entries and rows

```ruby
entry.text = 'typed'                 # fires 'changed'
entry.signal_emit('activate')        # as if Enter were pressed - note: signal_emit, not emit

adwaita_entry_row.text = 'typed'     # AdwEntryRow has the same text interface
switch_row.active = true             # fires notify::active
switch_row.active?

combo_row.selected = 2               # index into its model
combo_row.selected                   # read it back
```

`signal_emit` is the binding's name for firing a signal by hand; there is no
`emit`. Reach for it only when no property change will do the job - setting
`text` already fires `changed`, and driving the real property is the better
test because it exercises the same path the user's typing would.

Setting `text` triggers `changed`, so anything that recomputes sensitivity from
the field runs on its own. Check the result:

```ruby
d.check('Add is disabled while the title is blank') do
  dialog.title_row.text = ''
  !dialog.add_button.sensitive?
end
```

## 4. Lists, grids and selections

```ruby
selection.select_all
selection.unselect_all
selection.select_item(0, false)    # false = keep the existing selection
selection.selected?(3)
selection.n_items

# What is actually selected
(0...selection.n_items).select { |i| selection.selected?(i) }
                       .map { |i| selection.get_item(i) }
```

For a `Gio::ListStore` behind it:

```ruby
store.n_items
store.get_item(0)
(0...store.n_items).map { |i| store.get_item(i) }   # everything, in order
```

Sorting is worth checking through the store's order rather than the view:

```ruby
d.check('reversed title order') do
  model.pictures.map(&:title).first(3) == %w[photo_6 photo_5 photo_4]
end
```

`Gtk::ListBox` children, when you built rows directly:

```ruby
list_box.children                       # or first_child / next_sibling
list_box.children.select { |c| c.is_a?(Gtk::CheckButton) && c.active? }
```

## 5. File dialogs

`Gtk::FileDialog` is asynchronous and **raises** rather than yielding nil when
cancelled, so it cannot be driven from a test. Test the code behind it instead:

```ruby
# Rather than opening the dialog, call what its callback calls.
app.controller.load_pictures(uris)
app.controller.open_project(path)
```

Keep that logic in a method of its own so there is something to call. If the
dialog callback contains real logic inline, that logic is untestable - which is
a reason to extract it.

## 6. Async work

Work that runs on a thread and returns through `GLib::Idle` needs loop turns to
land. Give it its own step, and raise the interval if it does real I/O:

```ruby
GtkDriver.drive(MyApp.new, interval: 1000) do |d, app|
  d.step('start loading')      { app.controller.load_pictures(uris) }
  d.step('wait')               { }             # an empty step is a deliberate pause
  d.step('check what arrived') { d.check('all loaded') { model.n_pictures == 7 } }
end
```

If a step needs to wait for a condition rather than a fixed time, poll inside
it with a bounded loop instead of sleeping - `sleep` blocks the main loop and
guarantees the thing you are waiting for cannot happen:

```ruby
d.step('wait for the queue to drain') do
  50.times do
    break if app.controller.state == :idle

    GLib::MainContext.default.iteration(false)   # let the loop run, do not block
  end
end
```

## 7. Screenshots

GTK4 has no screenshot call. Paint the widget into a render node, hand it to a
renderer, and save the texture:

```ruby
renderer = Gsk::CairoRenderer.new
renderer.realize(nil)

snapshot = Gtk::Snapshot.new
Gtk::WidgetPaintable.new(widget).snapshot(snapshot, widget.width, widget.height)
snapshot.to_node.then { |node| renderer.render_texture(node, nil).save_to_png(path) }

renderer.unrealize
```

`scripts/gtk_driver.rb` wraps this as `d.shot('name')`. A nil render node means
the widget is not realised yet - present the window and let one tick pass.

Shooting a child widget rather than the window is useful when a dialog is
larger than the window, or when you want a close look at one pane:

```ruby
d.shot('preferences', dialog.preferences_page)
```

## 8. Reaching an object you did not keep

App code often does `SomeDialog.new(...).build.present(window)` without keeping
the wrapper, so there is no handle to poke. Three ways out, best first:

1. **Store it** while testing, or have the method return it. Usually the
   cleanest change, and harmless in production.
2. **Go through the widget**: `window.visible_dialog` gets you the GTK object,
   which is enough to close it or screenshot it.
3. **`ObjectSpace`** as a last resort, when you need the Ruby wrapper's methods
   and cannot change the code:

   ```ruby
   ObjectSpace.each_object(MyApp::Ui::DetailsDialog).first
   ```

   Fragile - it depends on GC timing and picks an arbitrary instance if more
   than one exists. Fine for a one-off diagnosis, not for a suite you keep.
