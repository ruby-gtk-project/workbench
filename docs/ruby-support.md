# Adding Ruby support to Workbench

Research notes: what "supported language" means in Workbench today, and what
adding Ruby would require.

## 1. What a "supported language" actually is

Workbench is a GJS (GNOME JavaScript) application. Every supported language is
integrated through the same set of seams. A language is "supported" when it
plugs into all of them:

| # | Integration point | Where |
|---|---|---|
| 1 | Language descriptor entry | `src/common.js` (`languages` array) |
| 2 | Editor tab + syntax highlighting | `src/window.blp` (`stack_code` StackPage + `$CodeView language_id`) |
| 3 | Dropdown registration | `src/window.js` (`dropdown_code_lang.model.append`) |
| 4 | `Document` subclass (load/save/format) | `src/langs/<lang>/<Lang>Document.js` |
| 5 | LSP client wiring (diagnostics/completion/format) | `src/langs/<lang>/<lang>.js` |
| 6 | A "run" strategy: Builder or Compiler | `src/langs/<lang>/{Builder,Compiler}.js` + `compile()` in `src/window.js` |
| 7 | A previewer that can execute the code | `src/Previewer/*` (internal GJS, or an out-of-process DBus previewer) |
| 8 | The `workbench` API exposed to demo code | per-language shim (`workbench.vala`, `workbench.rs`, python `WorkbenchModule`) |
| 9 | Toolchain availability gate | `src/Extensions/Extensions.js` + `Extensions.blp` |
| 10 | Library filter + demo discovery | `src/Library/Library.js`, `build-aux/library.js` |
| 11 | CLI lint/format/CI | `src/cli/main.js`, `src/cli/<lang>.js` |
| 12 | Packaging | `meson.build` files + `build-aux/re.sonny.Workbench*.json` |
| 13 | Demos | `demos/` submodule (separate repo `workbenchdev/demos`) |

### The language descriptor (`src/common.js`)

```js
{
  id: "python",
  name: "Python",
  panel: "code",             // "ui" | "code" | "style"
  extensions: [".py"],
  types: ["text/x-python"],
  document: null,            // filled in at runtime
  default_file: "main.py",   // the file created in each session/demo dir
  index: 3,                  // MUST match the dropdown_code_lang position;
                             // persisted in GSettings "code-language" (int)
  language_server: ["pylsp", "-v"],
  formatting_options: { tabSize: 4, insertSpaces: true, ... },
}
```

`index` is a persisted integer index into the dropdown. It is used by
`Session.getCodeLanguage()` (`src/sessions.js:160`) and by
`Library.js` when opening a demo in a specific language. Appending Ruby at the
end is safe; inserting it in the middle would silently reinterpret every user's
saved `code-language` setting.

### Three execution models

Workbench has exactly two previewers (`src/Previewer/Previewer.js`):

- **Internal** (`Internal.js`) — the widget tree is built inside the Workbench
  process itself. Used for JavaScript and TypeScript, because GJS can `import()`
  the user's module directly (`src/langs/javascript/Builder.js`) and hand the
  resulting exports back as *signal symbols* (`previewer.setSymbols`).
- **External** (`External.js` + `DBusPreviewer.js`) — Workbench spawns a
  separate process, connects to it over a private DBus server socket
  (`unix:path=$XDG_RUNTIME_DIR/...`), and drives it through the interface in
  `src/Previewer/previewer.xml`: `UpdateUi`, `UpdateCss`, `Run`, `OpenWindow`,
  `CloseWindow`, `Screenshot`, `EnableInspector`, plus `ColorScheme` property
  and `WindowOpen` / `CssParserError` signals.

There are two *implementations* of the external previewer, and this is the key
fork in the road:

1. **`workbench-previewer-module`** (`src/Previewer/previewer.vala`) — a Vala
   binary. `Run(filename, uri)` `dlopen`s a **shared library** and calls the
   C symbols `set_base_uri`, `set_builder`, `set_window`, `main`. Used by
   **Vala** (compiled with `valac -X -shared`) and by **Rust**
   (`src/langs/rust/template/lib.rs` exports the same `#[no_mangle]` symbols).
   Note `External.js` maps `"rust"` → the `"vala"` previewer.
2. **`workbench-python-previewer`** (`src/langs/python/python-previewer.py`) —
   a PyGObject script implementing the identical DBus interface, where
   `Run(filename, uri)` `importlib`-loads `main.py` and injects a synthetic
   `workbench` module into `sys.modules`.

**Ruby belongs in category 2**: an interpreted language gets its own previewer
process written in that language, implementing `previewer.xml`.

### The `workbench` API contract

Every language exposes the same three things to demo code:

| | JavaScript | Vala | Rust | Python |
|---|---|---|---|---|
| builder | `workbench.builder` | `workbench.builder` | `workbench::builder()` | `workbench.builder` |
| window | `workbench.window` | `workbench.window` | `workbench::window()` | `workbench.window` |
| resolve | `workbench.resolve(p)` | `workbench.resolve(p)` | `workbench::resolve(p)` | `workbench.resolve(p)` |

Plus: `print`/`stdout` must reach the console panel. That is free — the terminal
(`src/TermConsole.js`) just `tail -f`s a file that the `src/workbench` wrapper
pipes the whole app's stdout into via `script`, and subprocesses inherit it.

### Other per-language obligations

- **Syntax highlighting** comes from GtkSourceView's built-in `.lang` files
  (`language_id: 'python3'`, `'vala'`, `'rust'`). Only Blueprint ships a custom
  spec in `src/language-specs/`. GtkSourceView already ships `ruby.lang`.
- **Formatter/linter** are LSP-driven. `Document.format()` issues
  `textDocument/formatting` and applies the returned `TextEdit`s
  (`src/lsp/sourceview.js`). Diagnostics come from
  `notification::textDocument/publishDiagnostics` → `code_view.handleDiagnostics`.
  Python configures ruff through `workspace/didChangeConfiguration`
  (`PYTHON_LSP_CONFIG` in `common.js`) — the same hook exists for Ruby.
- **Toolchain gating**: Vala/Rust/TypeScript are optional Flatpak SDK
  extensions, so `Extensions.js` checks `/usr/lib/sdk/<ext>` exists and
  `window.js:runCode()` pops the Extensions dialog instead of running.
  Python needs no gate because it is in the runtime.
- **Library**: `build-aux/library.js` (a meson install script) walks
  `demos/src/*`, and derives `demo.languages` purely from **file existence**
  (`main.py` → python, `code.rs` → rust, …), writing `demos/index.json`.
  `Library.js` has its own hardcoded language list for the filter dropdown.
- **CLI**: `workbench-cli lint|check|format <lang> <files>` and
  `workbench-cli ci <demo dirs>` (used by `demos/Makefile` in CI) need a
  `src/cli/ruby.js` and entries in `src/cli/main.js`'s two language lists.

## 2. What Ruby specifically needs

### 2.1 The toolchain problem (biggest risk)

There is **no `org.freedesktop.Sdk.Extension.ruby` on Flathub** (verified against
the Flathub API; `vala`, `rust-stable`, `node24`, `typescript`, `golang`,
`dotnet9` exist — `ruby` and `php` do not). The GNOME runtime ships Python but
not Ruby.

So, unlike every existing language, Ruby has to be **vendored into the Flatpak
manifest** as build modules, in the style of `build-aux/modules/vte.json`,
`gom.json`, `libspelling.json`.

**Status: done.** Two modules are now wired into both
`build-aux/re.sonny.Workbench.json` and `build-aux/re.sonny.Workbench.Devel.json`,
after the Python LSP modules and before the `Workbench` module itself:

- **`build-aux/modules/ruby.json`** — CRuby 4.0.6 from `cache.ruby-lang.org`,
  autotools, `--enable-shared --enable-load-relative --disable-install-doc
  --disable-yjit --disable-zjit --disable-jemalloc`. libyaml 0.2.5 is built as a
  nested module because the freedesktop SDK does not ship it and psych (and
  therefore RubyGems' config handling) needs it. A `post-install` step asserts
  `json`, `psych` and `openssl` all loaded, so a silently-skipped extension
  fails the build rather than surfacing later.
- **`build-aux/modules/ruby-gnome.json`** — the full 21-gem ruby-gnome closure
  at 4.3.8, rooted at `adwaita` + `gtk4` + `gobject-introspection` +
  `gtksourceview5`. Flatpak
  builds are offline, so every gem is a pinned `file` source
  (`https://rubygems.org/downloads/<name>-<version>.gem` + sha256) and they are
  installed with a single `gem install --local` **in topological order** —
  RubyGems reaches for the network the moment a dependency is missing, so the
  order is load-bearing. `GEM_HOME` is deliberately *not* set, so gems land in
  Ruby's default `/app/lib/ruby/gems/<abi>` and `require "gtk4"` works at
  runtime with no environment setup.

The list is regenerated by
**`build-aux/modules/sources/generate-ruby-gems.py`**, which walks the RubyGems
dependency API, topologically sorts the closure and emits both the `sources`
array and the ordered `gem install` command:

```sh
./build-aux/modules/sources/generate-ruby-gems.py adwaita gtk4 gobject-introspection
```

**`build-aux/modules/sources/ruby-smoke-test.rb`** is installed as
`/app/bin/workbench-ruby-smoke-test` and opens an Adwaita window, reporting the
Ruby/gem versions and whether the `Workbench` typelib (needed later for
`Workbench::PreviewWindow`) is resolvable:

```sh
flatpak run --command=workbench-ruby-smoke-test re.sonny.Workbench.Devel
```

Verified: every pinned checksum matches the real download, and
`gem install --local --explain` against a clean `GEM_HOME` with the network
blocked resolves the whole set in the declared order, so the closure is
complete and offline-installable. Separately, **all 21 gems build and load on
Ruby 4.0.6** — every native extension compiles and `require "gtk4"; require
"adwaita"` succeeds. That was the open question about ruby-gnome 4.3.8 on Ruby
4.0, and the answer is yes.

That build was done in the Nix devshell (§2.2), not in the Flatpak, so the one
thing still unproven is the same compiles against the **GNOME 50 SDK's**
headers rather than nixpkgs'. Same gems, same compiler flags, different
prefix — low risk, but it needs one `flatpak-builder` run.

ruby-gnome has **no gem for WebKit or libshumate**. The Python previewer
`gi.require_version`s both, so the WebKit and Shumate demos have no Ruby
counterpart until someone writes those bindings or loads the typelibs through
`GObjectIntrospection::Loader` by hand.

A language server (`ruby-lsp`) is deliberately **not** in these modules yet; it
is step 5, and it is a single self-contained gem with its own closure.

Because Ruby is bundled rather than an optional SDK extension, it needs **no**
entry in `Extensions.js` and no availability gate in `runCode()` — same as
Python. That is the right trade: no extra install step for users.

This is the bulk of the work and should be prototyped first, because everything
else is cheap by comparison.

Also add to `Extensions.js` — or, if Ruby is bundled rather than an SDK
extension, *skip* the gate entirely (like Python). Bundling is preferable:
no extra install step for users.

### 2.2 The Nix devshell

`flake.nix` provides a devshell so the Ruby side can be developed and run
without a Flatpak build at all — which is what made everything below testable.

- `ruby_4_0` (4.0.6 in nixpkgs, the same version `ruby.json` pins), the GNOME
  libraries the previewer loads through GI, `ruby-lsp`, `flatpak-builder`, and
  the tooling the manifests need.
- `GEM_HOME` points into `.gems/` in the checkout, so gems never touch `~`.
- `GI_TYPELIB_PATH`, `LD_LIBRARY_PATH` and `XDG_DATA_DIRS` are set, the last
  because GTK aborts at startup without the gsettings schemas.
- One nixpkgs-specific wrinkle: the `pkg-config` gem resolves `Requires.private`
  transitively and dies on the first `.pc` it cannot find. Nixpkgs splits those
  across separate packages instead of propagating them from glib/gtk4/pango, so
  the shell has to list the whole closure explicitly — `libsysprof-capture`,
  `pcre2`, the xorg libs and so on. None of this applies inside the Flatpak,
  where the SDK is one flat prefix.

```sh
nix develop
./nix/install-ruby-gems.sh      # versions read from ruby-gnome.json
./nix/test-ruby-previewer.rb    # drives the previewer over D-Bus
```

`nix/install-ruby-gems.sh` takes its version list from
`build-aux/modules/ruby-gnome.json`, so local development cannot drift from
what the Flatpak ships.

### 2.3 The Ruby previewer

**Status: written and working.** `src/langs/ruby/ruby-previewer.rb` is a port
of `python-previewer.py`, built on `src/langs/ruby/gdbus_ext.rb`, launched by
`src/langs/ruby/workbench-ruby-previewer` and installed by
`src/langs/ruby/meson.build` (`subdir('langs/ruby')` in `src/meson.build`).

All seven interface methods, both signals and the `ColorScheme` property round
trip against a real D-Bus peer — see `nix/test-ruby-previewer.rb`, which stands
in for `DBusPreviewer.js`: it opens a private server on a unix socket, spawns
the previewer, and makes the same calls `External.js` makes. It presents a
window, runs a demo that reaches through the `Workbench` API, and writes a real
PNG from `Screenshot`.

#### `gdbus_ext.rb`

The Ruby counterpart of `gdbus_ext.py`. `Gio::DBusConnection#register_object`
does exist (ruby-gnome maps `g_dbus_connection_register_object_with_closures`
onto it), but two binding gaps make a helper unavoidable:

1. **Struct-array fields on the introspection info objects are broken.**
   `Gio::DBusNodeInfo#interfaces`, `DBusInterfaceInfo#methods` and
   `DBusMethodInfo#in_args` all return arrays of one-byte junk strings instead
   of objects. The `lookup_*` methods work, but there is no lookup for
   arguments — so argument signatures are scanned out of the XML rather than
   read back from GLib.
2. **`GLib::Variant.new` cannot build tuples.** `rbglib-variant.c` raises
   `NotImplementedError` for any type it does not special-case, and no tuple
   type is among them. Every reply and signal payload is a tuple, so they are
   rendered as GVariant text and re-parsed with `GLib::Variant.parse`, which
   *does* accept tuples. Element text comes from `GLib::Variant#to_s`, so GLib
   does the escaping and arbitrary strings survive intact.

The DSL mirrors the Python decorators, with CamelCase↔snake_case name mapping
and explicit opt-in so an ordinary helper method can never be reached over the
bus:

```ruby
class Previewer
  extend GDBus::Template
  dbus_interface File.read(PREVIEWER_XML), INTERFACE_NAME

  dbus_method def update_ui(content, target_id, original_id = "") ... end
  dbus_signal :window_open
  dbus_property :color_scheme
end
```

One structural difference from Python: `dbus_method` runs while the class body
is evaluated, so the interface XML has to be read before the class is defined,
not in the constructor.

#### ruby-gnome quirks the port ran into

Five ruby-gnome defects surfaced during this port. They are written up with
root causes, severities and runnable reproductions in **[FINDINGS.md](../FINDINGS.md)**;
`nix/ruby-gnome-findings.rb` reports which ones still reproduce after a gem
bump. In short: two are struct-field marshalling bugs (RG-1, RG-2), one is
missing tuple support in `GLib::Variant.new` (RG-3), one is a constructor that
silently returns `nil` (RG-4), and one is undocumented argument conversion
(RG-5).

`Gtk::Builder.new(string:)`, `expose_object`, `Gtk::IconTheme.get_for_display`,
`Gtk::StyleContext.add_provider_for_display`, `Gtk::Snapshot`,
`Gtk::WidgetPaintable` and `Graphene::Rect.new(x, y, w, h)` all behave as the C
docs suggest.

#### Where Ruby does better than Python

`run` uses `load(path, true)` — `load` re-executes on every call (unlike
`require`) and the wrap argument isolates each run in an anonymous module. The
Python previewer has to evict `sys.modules` and still cannot unload the old
module; its own comment looks forward to subinterpreters for this. Ruby gets it
for free.

#### Still to do here

- `Workbench::PreviewWindow` is loaded from the bundled typelib via
  `GObjectIntrospection::Loader`, with an `Adwaita::Window` fallback outside the
  Flatpak. The typelib path has only been exercised on the fallback branch so
  far — it needs a Flatpak run.
- The property setter does not emit `PropertiesChanged`. Nothing on the JS side
  listens for it, and the Python previewer does not either.

### 2.4 Workbench-side wiring (mechanical)

| File | Change |
|---|---|
| `src/common.js` | Add the `ruby` descriptor: `default_file: "main.rb"`, `extensions: [".rb"]`, `types: ["text/x-ruby"]`, `index: 5` (after TypeScript), `language_server: ["ruby-lsp"]`, `tabSize: 2`. Add a `RUBY_LSP_CONFIG` if RuboCop config needs pushing, mirroring `PYTHON_LSP_CONFIG`. |
| `src/langs/ruby/ruby.js` | `setup({document})` — copy of `python.js`: create LSP client, wire `publishDiagnostics` → `code_view.handleDiagnostics`, `didChange` on buffer modify. |
| `src/langs/ruby/RubyDocument.js` | Copy of `PythonDocument.js`; `format()` via `textDocument/formatting` + `applyTextEdits` + `saveState/restoreState`. |
| `src/langs/ruby/Builder.js` | Copy of `python/Builder.js`: `dbus_previewer.getProxy("ruby")` then `RunAsync(path, uri)`. |
| `src/Previewer/DBusPreviewer.js` | Add `PREVIEWER_TYPE_RUBY = "ruby"` → executable `workbench-ruby-previewer` (the launcher already exists). |
| `src/window.js` | Import `RubyDocument`/`RubyBuilder`, construct `document_ruby`, append `"Ruby"` to `dropdown_code_lang`, add the `language === "Ruby"` branch in `compile()` (`useExternal("ruby")` → `run()` → `open()` / fallback `useInternal()`). |
| `src/window.blp` | New `StackPage { name: 'Ruby'; child: $CodeView code_view_ruby { language_id: 'ruby'; } }`. |
| `src/Library/Library.js` | Add `{ id: "ruby", name: _("Ruby"), index: 6 }` to the filter list. |
| `build-aux/library.js` | `if (demo_dir.get_child("main.rb").query_exists(null)) languages.push("ruby")`. |
| `src/cli/main.js` | Add `ruby` to `createLSPClients` list and a `main.rb` branch in `ci()`. |
| `src/cli/ruby.js` | Copy of `cli/python.js`. |
| `build-aux/re.sonny.Workbench{,.Devel}.json` | Add the `ruby-lsp` module (ruby + ruby-gnome are already in). |
| `README.md` | Language-support table row. |

No changes needed for: syntax highlighting (GtkSourceView ships `ruby.lang`),
console output, sessions/autosave, screenshots, or the UI/CSS panels — those are
language-agnostic.

### 2.5 Demos (separate repo)

`demos/` is a git submodule of `workbenchdev/demos`. Full parity means a
`main.rb` in ~100 demo directories. `demos/Makefile` also needs a `format ruby`
line and the `.gitignore`/`clean` lists updated if the Ruby path generates any
scratch files (it should not — no compilation, no template project, unlike Rust's
`Cargo.toml`/`lib.rs` scaffolding or TypeScript's `tsconfig.json`).

Worth noting: Ruby needs **no** `setup<Lang>Project()` hook in `PanelCode.js`
(Rust/TS/JS each scaffold files on language switch) and **no** compile step —
making it the simplest language to integrate on the Workbench side, second only
to JavaScript.

## 3. Suggested order of work

1. ~~Prove the toolchain~~ — modules written (§2.1); still needs one real
   `flatpak-builder` run to confirm the native extensions compile.
2. ~~Port `gdbus_ext.py` → `gdbus_ext.rb`~~ — done, §2.3.
3. ~~Implement `Run` + the `Workbench` API module~~ — done; a demo runs under
   `nix/test-ruby-previewer.rb`.
4. Wire the Workbench-side files in §2.4 (all mechanical) — **next**.
5. Add `ruby-lsp` for diagnostics + formatting; add the CLI path.
6. Port demos, starting with `Welcome`.
