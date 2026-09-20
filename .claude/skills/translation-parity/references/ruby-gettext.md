# Wiring gettext into a Ruby GTK4 port

Everything here is the mechanical half. The discipline — which strings, which
keys, what counts as done — is in `SKILL.md`. Do not start here.

## The one decision

**Reuse upstream's catalogue; do not start a new one.** The port takes
upstream's `po/` directory, upstream's domain name, and upstream's msgids
verbatim. That single choice is what turns 78 donated languages into working
translations instead of a folder nobody reads.

The domain name is `meson.project_name()` from upstream's root `meson.build`
— `gnome-contacts`, never `gnome-contacts-rb`. A `.mo` is found at
`<path>/<lang>/LC_MESSAGES/<domain>.mo`, so the domain *is* the filename.
Rename it and every catalogue is orphaned.

## The gem

`glib2` does **not** give you `_()`. All it exposes is
`GLib::GetText.bindtextdomain` (a thin wrap of libintl's, for GTK's own
strings) and `GLib.language_names`. The app's own strings go through the
`gettext` gem, which is pure Ruby — it parses `.mo` files itself and needs no
C gettext tooling installed.

```ruby
# Gemfile
gem "gettext"
```

Its full marker set, and what `rxgettext` will extract from your source
(`lib/gettext/tools/parser/ruby.rb`):

| Marker | Aliases | Upstream equivalent |
|---|---|---|
| `_(msgid)` | `gettext` | `_()` |
| `n_(one, many, n)` | `ngettext` | `ngettext()` |
| `p_(ctxt, msgid)` | `pgettext` | `C_()` |
| `np_(ctxt, one, many, n)` | `npgettext` | `NC_()` + `ngettext` |
| `s_("ctxt|msgid")` | `sgettext` | `Q_()` |
| `N_(msgid)` | — | `N_()` — marks without translating |
| `Nn_(one, many)` | — | plural `N_()` |

## Binding

```ruby
# lib/main.rb
require "gettext"

module Contacts
  DOMAIN = "gnome-contacts"
  LOCALE_DIR = File.expand_path("../locale", __dir__)
end

class Contacts::Application < Adw::Application
  include GetText
  bindtextdomain Contacts::DOMAIN, path: Contacts::LOCALE_DIR
  # ...
end
```

Two things that bite:

- **`bindtextdomain` binds to a class, not to the process.** `include GetText`
  in one class does not give `_()` to the others. Either include and bind in
  every class that has strings, or — simpler and what a small port wants —
  include `GetText` once at the top level of a module every file already
  requires, and bind there.
- **Omitting `path:` makes lookup cwd-dependent.** The gem's default candidate
  list starts with `./locale/%{lang}/LC_MESSAGES/%{name}.mo`, which works when
  you run from the repo root and silently finds nothing when you do not. Pass
  `path:` explicitly.

Also call `GLib::GetText.bindtextdomain(domain, dir)` alongside it if the port
ships a GSettings schema or a `.desktop`/metainfo file — those are translated
by GLib and AppStream, not by the Ruby gem, and they read the same `.mo`.

## Moving the catalogue across

```sh
git checkout main -- po/                 # every .po, LINGUAS, POTFILES.in
```

Then rewrite `po/POTFILES.in` to the Ruby paths — it is a list of files
containing translatable strings, and upstream's list names `.vala` and `.blp`
files that no longer exist:

```
data/org.gnome.Contacts.desktop.in.in
data/org.gnome.Contacts.metainfo.xml.in.in
lib/contact_editor.rb
lib/contact_list.rb
...
```

`po/*.po` themselves are **not** edited by hand and **not** regenerated. They
are the donated work. The only thing that ever touches them is `rmsgmerge`,
when the message set changes.

## The Rakefile task

The gem ships `rxgettext`, `rmsgmerge` and `rmsgfmt` as pure Ruby, so the port
needs nothing from the system:

```ruby
# Rakefile
require "gettext/tools/task"

GetText::Tools::Task.define do |task|
  task.domain = "gnome-contacts"
  task.package_name = "gnome-contacts"
  task.files = Dir.glob("lib/**/*.rb") + Dir.glob("bin/*")
  task.po_base_directory = "po"
  task.mo_base_directory = "locale"
  task.locales = File.read("po/LINGUAS").split
end
```

That gives `rake gettext:po:update` (re-extract and merge — run only when the
message set genuinely changed) and `rake gettext:mo:update` (compile
`locale/<lang>/LC_MESSAGES/gnome-contacts.mo`). `locale/` is build output:
`.gitignore` it.

`task.locales` is read from `LINGUAS` rather than from `Dir.glob("po/*.po")` so
that a language which loses its `.po` file loses it loudly.

## The five Ruby traps

### 1. Interpolation destroys the key

This is the one that actually happens, and it happens before anybody thinks
about i18n:

```ruby
"Exported #{count} contacts to #{filename}"   # untranslatable, always
```

`#{}` is evaluated by the Ruby parser. By the time `_()` could see the string
it is already `"Exported 3 contacts to /home/x/a.vcf"`, which is in no
catalogue and never will be. `rxgettext` will not extract it either.

```ruby
format(n_("Exported %d contact", "Exported %d contacts", count), count)
```

Use `%`-style formatting on the *result* of the marker, never interpolation
inside it. Where a translation needs to reorder arguments, translators write
`%1$s` / `%2$s` and Ruby's `format` honours those.

### 2. Ruby's `format` rejects C length modifiers

Upstream msgids are written for C's `printf` and some carry `ll`, `l`, `h`,
`z`. gnome-contacts has `"%llu Selected"`, and:

```ruby
format("%llu Selected", 3)   # => ArgumentError: malformed format string - %l
```

The msgid must stay `"%llu Selected"` byte for byte or the translation is lost,
so the fix goes in the formatter, not the string:

```ruby
# ponytail: strips C length modifiers so upstream msgids format in Ruby;
# swap for real named-argument msgids only if upstream ever adopts them.
def fmt(msgid, *args)
  format(msgid.gsub(/%(\d+\$)?(?:ll|l|hh|h|z|j|t)([diouxXc])/, '%\1\2'), *args)
end
```

Note that `"%llu Selected"` and `"%d Selected"` are **two different messages**
in gnome-contacts, both meaning "N selected", because one counts a
`GLib.ListModel` and the other an `int`. Port both. Collapsing them to one
drops a translation.

### 3. Mnemonics are part of the msgid

`_("_Cancel")` — the underscore is the Alt-key mnemonic and it is inside the
translatable string, because translators pick a mnemonic that works in their
language. Keep it. Do not strip it and set `use_underline` separately with a
clean label; that is a different msgid.

### 4. Plural forms are the translation's business, not yours

```ruby
n_("Deleting %d contact", "Deleting %d contacts", n)
```

Pass both English forms and the count, always — even when `n` is known to be
plural at the call site, and even though English only has two forms. Polish has
three, Arabic has six, and the `.po` header's `Plural-Forms` expression picks
among them. Writing `n > 1 ? _("...contacts") : _("...contact")` in Ruby is
correct in English and wrong in most of the 78.

### 5. `N_()` marks, it does not translate

For strings in constants and tables — the type sets, the IM service names —
mark at definition with `N_()` and translate at display with `_()`:

```ruby
TYPES = [N_("Home"), N_("Work"), N_("Mobile")].freeze   # extracted, not translated
row.title = _(type)                                     # translated, at display
```

Getting this backwards gives a catalogue entry nobody looks up, or a lookup at
load time that uses the locale before it is set.

## Three things `rxgettext` will not do for you

### Translator comments are dropped by default

A `#. Translators:` comment is how upstream tells a translator that "Export"
is a verb, or that the `.desktop` `Keywords` semicolons must not be localised.
gnome-contacts has six, and every one of them prevents a specific, plausible
mistranslation.

The gem's Ruby parser sets `use_comment = false`, so `rxgettext` extracts none
of them unless told to:

```ruby
task.xgettext_options = ['--add-comments=TRANSLATORS']
```

and in the source the comment goes on the line before the marker:

```ruby
# TRANSLATORS: Export refers to the verb
_("Export")
```

Carry all six across when you port the strings they annotate. They are part of
the message, and losing them is invisible until a translation comes back wrong.

### `c-format` flags are not checked

gnome-contacts' po files carry **1,176 `#, c-format` flags**. GNU `msgfmt -c`
uses them to verify that every translation has the same format specifiers as
its msgid — the check that stops a translator's `%s` typo from crashing the
app at runtime in one language. The gem's tooling does not handle format flags
at all: it neither writes nor validates them.

Since the port reuses upstream's msgids, the flags are already in the po files
and `rmsgmerge` preserves them. Keep GNU `msgfmt -c` in the build to get the
check back — it is build-time only, so it belongs in `nativeBuildInputs` and
not in the runtime closure:

```sh
for po in po/*.po; do msgfmt -c --check-format -o /dev/null "$po" || exit 1; done
```

A port that compiles only with `rmsgfmt` ships 78 unchecked catalogues.

### RTL is not a translation problem until it is

`ar`, `he`, `fa` and `ug` all ship. GTK4 mirrors layout automatically, but only
for widgets whose spacing is expressed in direction-aware terms — `margin_start`
and `margin_end`, not `margin_left`/`margin_right`, and `halign: :start` rather
than a hardcoded left. Ruby ports tend to reach for whichever the binding
exposes first.

Run one of the four as part of the on-screen check:

```sh
LANGUAGE=ar LC_ALL=ar_AE.UTF-8 ruby bin/gnome-contacts-rb
```

A screenshot is enough — the failure is visible, never subtle.

## Non-Ruby files

Three message sources are not Ruby and are not handled by the gem:

| File | Translated by | Build step |
|---|---|---|
| `*.desktop.in` | `msgfmt --desktop` | merge at install |
| `*.metainfo.xml.in` | `msgfmt --xml` | merge at install |
| `*.gschema.xml` | GLib at runtime, via `gettext-domain=` | none — set the attribute |

The gschema one is free: add `gettext-domain="gnome-contacts"` to the
`<schemalist>` element and GLib translates `<summary>`/`<description>` from the
same `.mo`. The other two need `msgfmt` from the system `gettext` package at
*build* time only — add it to the flake's `nativeBuildInputs`, not to the
runtime closure.

A port with no `data/` directory has none of these files, and those messages
cannot be closed until the files exist. That is a component-parity gap as well
as a translation gap; say both.

## Verifying on screen

The catalogue can be perfect and the app still English — wrong `path:`, domain
typo, `bindtextdomain` in a class nothing instantiates. The only check that
catches it runs the app:

```sh
rake gettext:mo:update
LANGUAGE=de LC_ALL=de_DE.UTF-8 ruby bin/gnome-contacts-rb
```

Drive it headless per the `ruby-gtk-testing` skill and assert on one known
translated string — `"Adressbücher"` for gnome-contacts' `Address Books`.
One assertion is enough; it fails for every one of the wiring mistakes above.
