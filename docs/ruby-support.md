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
`gom.json`, `libspelling.json`:

- `build-aux/modules/ruby.json` — build CRuby from source (`./configure
  --prefix=/app --disable-install-doc --enable-shared`).
- `build-aux/modules/ruby-gnome.json` — the ruby-gnome gems. The essential one
  is **`gobject-introspection`** (which pulls `glib2`); `gtk4` and `libadwaita`
  gems on top. These are native extensions and need `pkg-config` + headers at
  build time. Gems must be vendored as `sources` (Flatpak builds are offline),
  which in practice means a generated sources list or `gem install --local`
  against pre-downloaded `.gem` archives.
- A language server module. **`ruby-lsp`** (Shopify) is the best fit: it is a
  single gem, speaks LSP over stdio, and provides diagnostics **and**
  formatting (RuboCop or `syntax_tree`) in one process — matching how
  `pylsp` + `ruff` are wired. Alternative: `solargraph`.

This is the bulk of the work and should be prototyped first, because everything
else is cheap by comparison.

Also add to `Extensions.js` — or, if Ruby is bundled rather than an SDK
extension, *skip* the gate entirely (like Python). Bundling is preferable:
no extra install step for users.

### 2.2 The Ruby previewer

New file `src/langs/ruby/ruby-previewer.rb`, a direct port of
`python-previewer.py`:

- Parse `previewer.xml` (argv[1]) and connect to the DBus address (argv[2]) with
  `Gio::DBusConnection.new_for_address_sync(..., :authentication_client)`.
- Register an object at `/re/sonny/workbench/previewer_module`, interface
  `re.sonny.Workbench.previewer_module`, implementing all methods/signals/the
  `ColorScheme` property. Python needed a helper for this
  (`src/langs/python/gdbus_ext.py`, a `DBusTemplate` decorator that turns an
  annotated class into a `Gio.DBusInterfaceInfo` registration) — **Ruby will
  need an equivalent helper**, e.g. `src/langs/ruby/gdbus_ext.rb`. This is a
  real chunk of work; ruby-gnome exposes `register_object` with a
  `MethodCallClosure`, but the ergonomics are low-level.
- `run(filename, uri)`: `load`/`instance_eval` `main.rb` fresh each time.
  Python uses `importlib` + module cache eviction; Ruby's `load` (not `require`)
  re-executes on every call, which is actually a better fit. Wrap in an
  anonymous module to limit leakage between runs.
- Expose the API. Idiomatic Ruby would be a top-level `Workbench` module with
  `Workbench.builder`, `Workbench.window`, `Workbench.resolve(path)` — the
  Python previewer's `WorkbenchModule.__getattr__` forwarding to live previewer
  state should be mirrored so re-running picks up new builder/window objects.
- Port `update_ui`, `update_css`, `screenshot` (needs Graphene/Gsk from the
  gems), `enable_inspector`, `reload_icons`, and the `Workbench::PreviewWindow`
  usage — that widget comes from the bundled
  `re.sonny.Workbench.libworkbench.gresource` + typelib, so Ruby must
  `require "gi"`-style load the `Workbench` typelib the same way Python does
  `gi.require_version("Workbench", "0")`.
- New launcher `src/langs/ruby/workbench-ruby-previewer` (mirroring the Python
  `sh` wrapper) + `src/langs/ruby/meson.build`, added via `subdir()` in
  `src/meson.build`.

### 2.3 Workbench-side wiring (mechanical)

| File | Change |
|---|---|
| `src/common.js` | Add the `ruby` descriptor: `default_file: "main.rb"`, `extensions: [".rb"]`, `types: ["text/x-ruby"]`, `index: 5` (after TypeScript), `language_server: ["ruby-lsp"]`, `tabSize: 2`. Add a `RUBY_LSP_CONFIG` if RuboCop config needs pushing, mirroring `PYTHON_LSP_CONFIG`. |
| `src/langs/ruby/ruby.js` | `setup({document})` — copy of `python.js`: create LSP client, wire `publishDiagnostics` → `code_view.handleDiagnostics`, `didChange` on buffer modify. |
| `src/langs/ruby/RubyDocument.js` | Copy of `PythonDocument.js`; `format()` via `textDocument/formatting` + `applyTextEdits` + `saveState/restoreState`. |
| `src/langs/ruby/Builder.js` | Copy of `python/Builder.js`: `dbus_previewer.getProxy("ruby")` then `RunAsync(path, uri)`. |
| `src/Previewer/DBusPreviewer.js` | Add `PREVIEWER_TYPE_RUBY = "ruby"` → executable `workbench-ruby-previewer`. |
| `src/window.js` | Import `RubyDocument`/`RubyBuilder`, construct `document_ruby`, append `"Ruby"` to `dropdown_code_lang`, add the `language === "Ruby"` branch in `compile()` (`useExternal("ruby")` → `run()` → `open()` / fallback `useInternal()`). |
| `src/window.blp` | New `StackPage { name: 'Ruby'; child: $CodeView code_view_ruby { language_id: 'ruby'; } }`. |
| `src/Library/Library.js` | Add `{ id: "ruby", name: _("Ruby"), index: 6 }` to the filter list. |
| `build-aux/library.js` | `if (demo_dir.get_child("main.rb").query_exists(null)) languages.push("ruby")`. |
| `src/cli/main.js` | Add `ruby` to `createLSPClients` list and a `main.rb` branch in `ci()`. |
| `src/cli/ruby.js` | Copy of `cli/python.js`. |
| `src/meson.build` | `subdir('langs/ruby')`. |
| `build-aux/re.sonny.Workbench{,.Devel}.json` | Add the ruby + ruby-gnome + ruby-lsp modules. |
| `README.md` | Language-support table row. |

No changes needed for: syntax highlighting (GtkSourceView ships `ruby.lang`),
console output, sessions/autosave, screenshots, or the UI/CSS panels — those are
language-agnostic.

### 2.4 Demos (separate repo)

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

1. Prove the toolchain: a Flatpak manifest that builds CRuby + the
   `gobject-introspection`/`gtk4`/`libadwaita` gems inside `org.gnome.Sdk//50`,
   and can open a GTK4 window. **Everything else is blocked on this.**
2. Port `gdbus_ext.py` → `gdbus_ext.rb` and get a minimal
   `ruby-previewer.rb` answering `UpdateUi` + `OpenWindow`.
3. Implement `Run` + the `Workbench` API module; get one demo running.
4. Wire the Workbench-side files in §2.3 (all mechanical).
5. Add `ruby-lsp` for diagnostics + formatting; add the CLI path.
6. Port demos, starting with `Welcome`.
