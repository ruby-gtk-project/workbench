---
name: ruby-gtk-testing
description: Test a Ruby GTK4/Libadwaita app by actually running it and driving its UI headlessly - clicking through dialogs, checking widget state, and capturing screenshots you can look at. Use this whenever you have written or changed Ruby GTK code and want to know whether it really works, when the user asks to test/verify/check/try a GTK app or says "does it run?", when a widget or dialog misbehaves and you need to reproduce it, when porting an app and needing to confirm the port matches, or before reporting any Ruby GTK work as done. Also use it when you are tempted to claim a GTK change works based only on `ruby -c` or a successful require - syntax checks prove nothing about a UI.
---

# Testing Ruby GTK4 Apps by Driving Them

A GTK app that loads is not a GTK app that works. `ruby -c` passes on code that
builds an empty window; `require` succeeds on code whose every button is wired
to the wrong handler. The only way to know is to run the app, poke it, and look
at what happened.

You can do all of that headlessly, and you can look at the screenshots
yourself - which means a whole class of bugs (blank labels, dialogs that never
open, controls that render insensitive, panes that never switch) becomes
visible rather than theoretical.

## Two kinds of test, and the order to write them

Separate the logic from the UI, because they fail differently and cost
differently to run:

1. **Plain checks on the non-widget code** - models, parsing, persistence,
   serialisation. These need no display and no main loop, so they run in
   milliseconds and can be exhaustive. Round trips are especially worth
   pinning: save-then-load, encode-then-decode, join-then-split.
2. **Driving the UI** - does the window build, does the dialog open, does
   editing a field actually change the model. Slower, so aim it at the wiring
   and the things a screenshot can reveal.

Write the first kind for anything expressible without a widget. Reach for the
second when the question is genuinely about the interface.

## Running headlessly

GTK4 renders to an offscreen surface when there is no display, and screenshots
come out identical to a real session. **No Xvfb, no `GDK_BACKEND` fiddling, no
compositor.** If your environment might have a stale `DISPLAY`, clear it:

```sh
env -u DISPLAY -u WAYLAND_DISPLAY ruby test/drive_main_window.rb
```

Point the app at a scratch config directory so a test run never reads or
scribbles on the user's real settings:

```ruby
ENV['XDG_CONFIG_HOME'] = Dir.mktmpdir
```

## The core obstacle: GTK needs its main loop back

This is what makes UI testing feel impossible until you see the trick. GTK does
its work *between* your callbacks. Widgets are not laid out, dialogs do not
exist, and nothing is rendered until control returns to the main loop:

```ruby
# Does not work. The dialog has not been created yet, so this sees nothing.
view.edit_details
assert view.window.visible_dialog
```

So every action needs its own turn of the loop. Run your steps one per timeout
tick and each one sees the settled result of the last:

```ruby
GLib::Timeout.add(500) do
  run_next_step   # returns true to be called again, false when done
end
```

`scripts/gtk_driver.rb` in this skill packages that up, along with screenshots
and a watchdog. Copy it into the project's `test/` directory (it has no
dependencies beyond `gtk4`) and write:

```ruby
require_relative 'gtk_driver'

GtkDriver.drive(MyApp.new, shots: 'tmp/shots') do |d, app|
  d.window { app.main_view.window }

  d.step('load some files') do
    app.controller.load_pictures(uris)
  end

  d.step('the grid fills in') do
    d.check('7 items loaded') { app.controller.model.n_pictures == 7 }
    d.check('grid page is showing') { app.main_view.main_stack.visible_child_name == 'pictures' }
    d.shot('01-grid')
  end
end
```

It prints each step and check, writes PNGs, and exits non-zero if any check
failed or any step raised - so it works as a test command directly. A step that
raises is reported but does not stop the run, because the later steps usually
tell you how far the damage spread. A watchdog quits the app if the steps never
finish, since a hung run gives you nothing to read.

**Then read the screenshots.** This is the part that pays. Assertions confirm
what you already thought to ask about; the picture shows you what you did not.
Every UI bug found while writing this skill's companion port was found by
looking, not by asserting.

## Reaching into the app

The house style is what makes this pleasant: widgets are memoized methods, so
any widget has a name you can call. `app.main_view.title_row.text = 'x'` is a
legitimate way to drive the UI, and it is far steadier than synthesising input
events.

Two things follow. Keep widget methods public - the memoized-method section
sits at the bottom of the class, and a stray `private` above it locks the tests
out of the whole UI for no benefit. And prefer calling the handler the way the
widget would (`button.activate`, `row.text = ...`) over calling your own
private method directly, so the wiring is under test and not just the logic.

For anything more specific - opening and closing Adwaita dialogs, list
selections, entries, file dialogs, async work, custom widgets - see
`references/recipes.md`.

## What is worth checking

Aim at the seams, where a mistake is silent:

- **Wiring**: does activating this control change the model? Multi-select edits
  are a good target, since they are easy to get subtly wrong (writing one
  picture's title over all of them).
- **State transitions**: empty state to populated, idle to busy, unauthorised
  to authorised. Screenshot both sides.
- **Round trips through the UI**: create something, save, reload, and confirm
  it comes back the same. This catches serialisation bugs that unit tests on
  the model alone can miss, because the UI builds the object differently.
- **Refusals**: the app should decline to do the impossible. Trying to upload
  with no account should leave the state untouched, not crash and not silently
  half-succeed.
- **Rendering**: labels populated, controls sensitive or insensitive as
  intended, the right stack page visible. Mostly a screenshot question.

## Traps worth knowing

- **Dialogs stack.** Opening a second dialog without closing the first leaves
  both, and your screenshot shows the wrong one. Close as you go:
  `window.visible_dialog&.close`.
- **Startup dialogs interfere.** Apps that present something on idle at launch
  (a first-run or authorisation prompt) will be sitting in front of your first
  screenshot. Dismiss it in step one - that also tests it opens at all.
- **A test file can match itself.** A check that searches for a marker string
  will find that string in its own source if pointed at the test file. Use a
  temp file with known content instead.
- **`Gtk::FileDialog` is async and raises on cancel**, so it cannot be driven
  by clicking. Test the code behind it by calling the method the callback calls.
- **Screenshots need a realised widget.** Shoot after the window is presented
  and at least one tick has passed, or the render node comes back nil.

## Reporting

Say what you ran and what it showed. "13 checks pass and the grid renders with
all 7 thumbnails" is a claim someone can check. "Should work" is not - and
after driving the app, you no longer have any reason to write it.

If something is genuinely untestable here - anything needing real credentials
or a real network service - say so plainly and name it, rather than letting a
green run imply more coverage than it has.
