# workbench — Ruby port

This branch is an empty `ruby` orphan branch. The upstream code (the original
implementation of workbench) lives on the fork's other branches; this branch is
where the Ruby GTK4 / Libadwaita port is written.

## Skills — use them

Six skills are installed in `.claude/skills/`. They are not optional reading.

- **ruby-gtk** — the house style for Ruby GTK4/Libadwaita: the declarative
  memoized-widget pattern, Adwaita binding quirks, worked examples. Load it
  before writing or reviewing ANY Ruby GTK code, including single widgets, and
  before planning a port. The bindings are quirky enough that code written from
  memory is unreliable.
- **ruby-gtk-testing** — run the app headlessly and drive its UI: click through
  dialogs, assert widget state, capture screenshots. Use it before claiming any
  GTK change works. `ruby -c` and a successful `require` prove nothing about a
  UI.
- **component-identification** — enumerate the UI a GTK app actually has:
  every widget, its CSS classes, signals and actions, as an inventory.
- **component-parity** — prove the port builds the same components as the
  original, compared per component, recorded in `COMPONENT_PARITY.md`.
- **test-parity** — prove the port's suite has exactly one test for every
  upstream test, recorded in `TEST_PARITY.md`.
- **accountability-ensurance** — hunt the prose that turns a missing feature
  into a settled decision. A gap is a gap, not a design choice.

The port is done when component parity and test parity both hold. Neither
implies the other.

## Setup

`direnv allow` (or `nix develop`) gets Ruby, GTK4, Libadwaita and the
introspection typelibs. Then `bundle install`.

## Style

`.rubocop.yml` plus the custom cops in `cops/` are enforced: no `return`, no
modifier `if`, no conditional assignment, `tap` where it applies, and fixed
multi-line argument/hash layout. Run `bundle exec rubocop` before committing.
