# ruby-gnome findings

Defects and surprises hit while writing Workbench's Ruby previewer
(`src/langs/ruby/`), with the workaround used for each.

Every entry has a runnable reproduction:

```sh
nix develop --command ./nix/ruby-gnome-findings.rb
```

That script reports each item as **PRESENT** or **FIXED**, so after bumping the
gems in `build-aux/modules/ruby-gnome.json` it says which workarounds can be
deleted. As of ruby-gnome **4.3.8** on Ruby **4.0.6**, all six are PRESENT.

None of these are worked around by patching the gems. Every workaround lives in
`src/langs/ruby/gdbus_ext.rb` and `ruby-previewer.rb`, in ordinary Ruby, so
nothing has to be un-patched when upstream fixes them.

| ID | Severity | Summary |
|----|----------|---------|
| [RG-1](#rg-1) | bug | Array-typed struct fields return junk |
| [RG-2](#rg-2) | bug | Same, for `DBusInterfaceInfo#methods` / `DBusMethodInfo#in_args` |
| [RG-3](#rg-3) | missing feature | `GLib::Variant.new` cannot build tuples |
| [RG-4](#rg-4) | API trap | `DBusConnection.new_for_address` is the async call and returns `nil` |
| [RG-5](#rg-5) | undocumented behaviour | Closure arguments arrive converted, not as `GLib::Variant` |
| [RG-6](#rg-6) | API trap | `require` does not register GTypes, so `Gtk::Builder` silently returns `nil` |

---

## RG-1

### Array-typed struct fields return junk instead of structs

`Gio::DBusNodeInfo#interfaces` should be an array of `Gio::DBusInterfaceInfo`.
It is an array of one-byte junk strings. The *length* is right; only the
elements are wrong.

```ruby
info = Gio::DBusNodeInfo.new(xml)
info.interfaces          # => [""]        expected [#<Gio::DBusInterfaceInfo>]
info.interfaces.first.name
# NoMethodError: undefined method 'name' for an instance of String
```

**Root cause.** In the `gobject-introspection` gem,
`ext/gobject-introspection/rb-gi-field-info.c` handles struct field reads with a
`switch` on the type tag, and the array case is a bare fallthrough:

```c
case GI_TYPE_TAG_FILENAME:
case GI_TYPE_TAG_ARRAY:
  break;                       /* processed stays FALSE */
```

With `processed == FALSE` it falls through to `g_field_info_get_field()`, which
fills the union's pointer member, and the generic converter then reads that
pointer as a UTF-8 string. Hence one-byte garbage rather than an error.

**Impact.** Any GI struct with an array field is unreadable, which is most of
the D-Bus introspection types. This is not D-Bus-specific.

**Workaround.** Never enumerate; only ever look up by name. `lookup_interface`
and `lookup_method` are real methods rather than field reads and return proper
objects:

```ruby
iface = Gio::DBusNodeInfo.new(xml).lookup_interface(name)   # works
```

Where a lookup does not exist — see RG-2 — the information is taken from the
XML instead.

---

## RG-2

### `DBusInterfaceInfo#methods` and `DBusMethodInfo#in_args` likewise

The same defect as RG-1, one level down, and this one has no escape hatch:

```ruby
iface.methods                          # => ["", "", ...]
iface.lookup_method("UpdateUi")        # => #<Gio::DBusMethodInfo>  (fine)
iface.lookup_method("UpdateUi").in_args # => ["", "", ""]
```

There is a `lookup_method`, but **no lookup for arguments**, so argument
signatures cannot be recovered from GLib at all.

**Impact.** A generic D-Bus object helper cannot learn what types a method
takes or returns, which is exactly what it needs to marshal replies.

**Workaround.** `GDBus::InterfaceSpec` in `src/langs/ruby/gdbus_ext.rb` scans
the signatures out of the introspection XML itself and keeps its own table of
methods, signals and properties. The `Gio::DBusInterfaceInfo` built from the
same XML is still what gets handed to `register_object`, so GLib remains the
authority on the wire; the scanner only supplies the type strings the bindings
will not give back.

It is a scanner rather than an XML parse because `rexml` is a bundled gem and
is not always installed — nixpkgs' Ruby ships without it — and the only
document it is ever given is `src/Previewer/previewer.xml`, which Workbench
generates itself. It raises on anything it does not recognise rather than
skipping it.

---

## RG-3

### `GLib::Variant.new` cannot build tuple types

```ruby
GLib::Variant.new(["a", "b", "c"], "(sss)")
# NotImplementedError: TODO: Ruby -> GVariant((sss)): ["a", "b", "c"]
```

**Root cause.** `glib2`'s `ext/glib2/rbglib-variant.c` converts Ruby to GVariant
with an `if`/`else if` chain over specific types — booleans, the integer
widths, strings, object paths, string arrays, bytestrings — and ends in

```c
} else {
    rb_raise(rb_eNotImpError, "TODO: Ruby -> GVariant(%.*s): %s", ...);
}
```

No tuple type is in the chain, and the error message says as much.

**Impact.** Every D-Bus method reply and every signal payload is a tuple, so
without a workaround a Ruby process can receive D-Bus calls but cannot answer
them or emit signals.

**Workaround.** `GDBus.tuple` renders each element with `GLib::Variant#to_s` —
GLib's own text format, correctly escaped — joins them, and re-parses the
result with `GLib::Variant.parse`, which *does* handle tuples:

```ruby
def self.tuple(values, signature)
  return nil if signature == "()"

  elements = values.map { |value| variant_text(value) }
  # A one-element tuple needs the trailing comma: "(true,)", not "(true)".
  text = "(#{elements.join(", ")}#{elements.size == 1 ? "," : ""})"
  GLib::Variant.parse(text, signature)
end
```

Two details make this safe rather than a string-splicing hack. Element text
comes from GLib, not from Ruby's `inspect`, so quotes, backslashes and newlines
round trip exactly — verified against `%Q{it's "quoted"\nand newline}`. And the
signature passed to `parse` comes from the interface XML, so the wire types are
what was declared rather than whatever `parse` would have inferred from the
text.

Note also that `GLib::Variant.parse` takes `(text, type)`, not `(type, text)`,
and rejects a `GLib::VariantType` object where it wants the type *string*.

---

## RG-4

### `DBusConnection.new_for_address` is the async call and silently returns `nil`

```ruby
Gio::DBusConnection.new_for_address(address, flags)   # => nil
```

GI exposes six relevant entry points — `new`, `new_finish`, `new_sync`,
`new_for_address`, `new_for_address_finish`, `new_for_address_sync`. ruby-gnome
folds the *constructors* (`new_sync`, `new_for_address_sync`) into `.new` and
dispatches on the arguments, which leaves the plain function
`g_dbus_connection_new_for_address` — the asynchronous one, returning `void` —
holding the obvious name.

So the method whose name matches the C sync function is the async one, and
because the async function returns nothing, it returns `nil` with no error, no
warning, and a connection that was in fact established on the server side.

**Workaround.** Use `.new`, and check for `nil` anyway:

```ruby
connection = Gio::DBusConnection.new(
  address, Gio::DBusConnectionFlags::AUTHENTICATION_CLIENT
)
abort "could not connect to #{address}" if connection.nil?
```

The same folding applies elsewhere: `Gio::DBusServer.new(...)` is
`g_dbus_server_new_sync`, and there is no `.new_sync`. `Gio::DBusNodeInfo.new(xml)`
is `g_dbus_node_info_new_for_xml`; there is no `.new_for_xml`.

---

## RG-5

### Closure arguments arrive already converted, not as `GLib::Variant`

The `method_call` closure passed to `register_object` receives its `parameters`
argument as a plain Ruby `Array`, and `set_property` receives an unwrapped Ruby
value — not the `GVariant`s the C signature describes.

```ruby
lambda { |_c, _s, _p, _i, _m, parameters, invocation|
  parameters.class    # => Array   (a "(sss)" call arrives as three Strings)
  parameters.value    # NoMethodError: undefined method 'value' for an instance of Array
}
```

`Gio::DBusConnection#call_sync` returns a converted `Array` too, so the same
applies to callers.

This is convenient and probably deliberate, but it is undocumented and it means
code written from the C or PyGObject signature — where `.value` is how you
unwrap — fails at runtime with a confusing error.

**Workaround.** Accept either shape, so the code does not depend on the
behaviour staying put:

```ruby
def self.ruby_values(parameters)
  case parameters
  when nil then []
  when GLib::Variant then Array(parameters.value)
  when Array then parameters
  else [parameters]
  end
end
```

Note the asymmetry: arguments come in converted, but the closure's *return*
still has to be a real `GLib::Variant` (hence RG-3).

---

## RG-6

### `require` does not register GTypes, so `Gtk::Builder` silently returns `nil`

Every ruby-gnome gem loads its typelib **lazily**, from `const_missing`:

```ruby
module WebKitGtk
  class << self
    def const_missing(name)
      init            # this is what actually loads the WebKit typelib
      ...
```

So after `require "webkit-gtk"` the `WebKitWebView` GType is still not
registered, and building a UI definition that uses it does not raise — it
hands back `nil`:

```ruby
require "webkit-gtk"
Gtk::Builder.new(string: ui).get_object("web")   # => nil

WebKitGtk::WebView                               # touching it loads the typelib
Gtk::Builder.new(string: ui).get_object("web")   # => WebKitGtk::WebView
```

The same applies to `gtksourceview5` and `GtkSource::View`.

**Impact.** Anything that builds widgets from XML rather than from Ruby — which
is exactly what a Workbench previewer does — sees a missing widget instead of
an error, and the failure surfaces far from its cause.

**Workaround.** Touch the constants at startup, which is the direct counterpart
of the `GObject.type_ensure()` calls at the top of `python-previewer.py`:

```ruby
GtkSource::View
WebKitGtk::WebView
```

---

## Not bugs, but not guessable either

Naming and namespace differences that cost time without being defects. The
Adwaita entries come from the `ruby-gtk` skill's `adwaita-quirks.md`, which is
worth reading before writing any Adwaita code.

| Expected from C/Python | Actual in ruby-gnome |
|---|---|
| `Adw::Window`, `Adw::StyleManager` | **`Adwaita::`**, not `Adw::` |
| `Gtk.init` / `Adw.init` | Neither exists; both gems initialise on `require` |
| `Adwaita::Application` | Broken; use `Gtk::Application` with `Adwaita::ApplicationWindow` |
| `WebKit` (module), gem `webkit-gtk6` | Module **`WebKitGtk`**, gem **`webkit-gtk`** |
| `Gtk::Window.set_interactive_debugging(bool)` | `Gtk::Window.interactive_debugging = bool` also works |
| `PyGObject`'s missing Graphene constructors | `Graphene::Rect.new(x, y, w, h)` works — Ruby is *better* here |

One thing Ruby does better than the Python previewer: reloading a demo.
`python-previewer.py` has to evict `sys.modules` and still cannot truly unload
the previous module — its own comment looks forward to PEP 554 subinterpreters.
Ruby's `load(path, true)` re-executes the file every call and wraps it in a
fresh anonymous module, so constants and top-level methods do not leak between
runs.

## Gaps rather than bugs

Of the libraries `python-previewer.py` pulls in, ruby-gnome covers all but one.
The [upstream binding list](https://github.com/ruby-gnome/ruby-gnome) is the
thing to check — gem names do not always match the library name, and guessing
them is how you conclude a binding is missing when it is not:

| Library | ruby-gnome gem | Ruby module |
|---|---|---|
| GTK 4 | `gtk4` | `Gtk` |
| Libadwaita | `adwaita` | **`Adwaita`** |
| GtkSourceView 5 | `gtksourceview5` | `GtkSource` |
| WebKitGTK 6.0 | **`webkit-gtk`** | **`WebKitGtk`** |
| libshumate | *none* | — |

`webkit-gtk` 4.3.8 depends on `gtk4 = 4.3.8` and binds the **WebKit 6.0**
typelib, which is the GTK4 one — the same version `python-previewer.py` asks
for. It is in the gem closure and the previewer loads it.

**libshumate** genuinely has no binding: there is no `shumate` directory
upstream and nothing on rubygems. Until one exists, the Shumate demos have no
Ruby counterpart, unless the typelib is loaded by hand through
`GObjectIntrospection::Loader` the way the previewer already loads the
`Workbench` typelib.

## Upstream

None of these have been reported yet. RG-1/RG-2 (`rb-gi-field-info.c`) and RG-3
(`rbglib-variant.c`) are concrete enough to file against
[ruby-gnome/ruby-gnome](https://github.com/ruby-gnome/ruby-gnome) with the
reproductions in `nix/ruby-gnome-findings.rb`.
