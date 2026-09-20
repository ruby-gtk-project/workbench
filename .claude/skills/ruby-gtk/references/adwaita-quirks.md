# Ruby GTK4 Adwaita Patterns â€” Binding Quirks and Solutions

This document catalogs differences between Adwaita's C/Vala API and the Ruby bindings, with correct patterns for each.

---

## Table of Contents

1. [Namespace](#1-namespace)
2. [Constructor Signatures](#2-constructor-signatures)
3. [Widgets That Work Normally](#3-widgets-that-work-normally)
4. [Widgets With Quirks](#4-widgets-with-quirks)
5. [Broken Widgets and Unsupported APIs](#5-broken-widgets-and-unsupported-apis)
6. [Working Adwaita App Pattern](#6-working-adwaita-app-pattern)

---

## 1. Namespace

**The Ruby Adwaita bindings use `Adwaita::` not `Adw::`.**

```ruby
# âŒ WRONG
Adw::Toast.new('Message')
Adw::NavigationSplitView.new

# âœ… RIGHT
Adwaita::Toast.new('Message')
Adwaita::NavigationSplitView.new
```

**Import:**
```ruby
require 'adwaita'
```

---

## 2. Constructor Signatures

Ruby GTK bindings often differ from C/Vala in how constructors work:

| Pattern | C/Vala | Ruby |
|---------|--------|------|
| Keyword args | `new(child: widget, title: "X")` | Often fails |
| Positional args | N/A | Usually works |
| No-arg + setters | `new()` then set properties | Sometimes works |

**Rule: When keyword arguments fail, try positional arguments in the order shown in the error message.**

---

## 3. Widgets That Work Normally

These Adwaita widgets work as expected with no-argument constructors:

```ruby
# These all work with .new and property setters
def toast_overlay = @toast_overlay ||= Adwaita::ToastOverlay.new
def toolbar_view = @toolbar_view ||= Adwaita::ToolbarView.new
def header_bar = @header_bar ||= Adwaita::HeaderBar.new
def bin = @bin ||= Adwaita::Bin.new
def clamp = @clamp ||= Adwaita::Clamp.new
def status_page = @status_page ||= Adwaita::StatusPage.new

# NavigationSplitView works normally
def split_view
  @split_view ||= Adwaita::NavigationSplitView.new.tap do |sv|
    sv.sidebar_width_fraction = 0.3
    sv.min_sidebar_width = 260
    sv.max_sidebar_width = 360
  end
end

# Toast requires message in constructor
def toast = Adwaita::Toast.new('Message text')

# Avatar takes size, text, show_initials
def avatar = Adwaita::Avatar.new(96, nil, true)
```

---

## 4. Widgets With Quirks

### Adwaita::NavigationPage

**Requires positional arguments: `child`, `title`**

```ruby
# âŒ WRONG - keyword arguments
Adwaita::NavigationPage.new(child: toolbar, title: 'Contacts')

# âŒ WRONG - no arguments then set properties
Adwaita::NavigationPage.new.tap do |page|
  page.child = toolbar
  page.title = 'Contacts'
end

# âœ… RIGHT - positional arguments
def list_pane_page
  @list_pane_page ||= Adwaita::NavigationPage.new(sidebar_toolbar, 'Contacts')
end
```

**Consequence: Child must be created before the NavigationPage.**

This affects memoization order. The child widget method must be defined and will be called when NavigationPage is first accessed:

```ruby
# sidebar_toolbar is created first, then passed to NavigationPage
def list_pane_page
  @list_pane_page ||= Adwaita::NavigationPage.new(sidebar_toolbar, 'Contacts')
end

def sidebar_toolbar
  @sidebar_toolbar ||= Adwaita::ToolbarView.new
end
```

### Adwaita::PreferencesGroup

Works normally but `add()` method is used to add rows:

```ruby
def preferences_group
  @preferences_group ||= Adwaita::PreferencesGroup.new.tap do |group|
    group.title = 'Section Title'
  end
end

# In build, use add() not append()
preferences_group.add(some_row)
```

### Adwaita::EntryRow

Works normally:

```ruby
def name_row
  @name_row ||= Adwaita::EntryRow.new.tap do |row|
    row.title = 'Full Name'
    row.text = 'Initial value'
  end
end
```

### Adwaita::ActionRow

Works normally:

```ruby
def action_row
  @action_row ||= Adwaita::ActionRow.new.tap do |row|
    row.title = 'Title'
    row.subtitle = 'Subtitle'
    row.activatable = true
  end
end
```

### Adwaita::PreferencesRow

Works normally but typically you set `child` manually:

```ruby
def custom_row
  @custom_row ||= Adwaita::PreferencesRow.new.tap do |row|
    row.activatable = false
    row.child = some_widget
  end
end
```

---

## 5. Broken Widgets and Unsupported APIs

### Adwaita::Application

**DO NOT USE.** The Ruby bindings have type interface issues.

```ruby
# BROKEN - inheritance doesn't work
class App < Adwaita::Application
  # Type errors when passing to ApplicationWindow
end

# BROKEN - even composition fails
def app
  @app ||= Adwaita::Application.new('org.example.app', :default_flags)
end

# WORKING - use the Gtk version instead
def app
  @app ||= Gtk::Application.new('org.example.contacts', :default_flags)
end
```

### Adwaita::ApplicationWindow

**Was broken; works as of ruby-gnome 4.3.8.** Earlier notes in this guide said
to use `Gtk::ApplicationWindow` instead. On 4.3.8 the Adwaita version
constructs from a `Gtk::Application`, accepts actions via `add_action`, and
takes `title` and `icon_name` normally.

**Prefer it, because it is what makes `Adwaita::Dialog` present inside the
window.** Presented on a `Gtk::ApplicationWindow`, an `AdwDialog` falls back to
spawning a separate toplevel - the dialog still works, but it is a floating
window rather than the in-window sheet the design expects.

```ruby
# The application object still comes from Gtk - only the window changes.
def app = @app ||= Gtk::Application.new('org.example.app', :default_flags)

def window
  @window ||= Adwaita::ApplicationWindow.new(app).tap do |win|
    win.title = 'My App'
    win.set_default_size(800, 600)
  end
end
```

**It takes `content=`, not `child=`.** `AdwApplicationWindow` owns its own
internal layout, so assigning `child` is wrong:

```ruby
# WRONG - Gtk::Window API
window.child = toast_overlay

# RIGHT
window.content = toast_overlay
```

To check which behaviour you are getting, read
`Gtk::Window.list_toplevels.length` before and after `dialog.present(window)`:
it stays at 1 with an Adwaita window and goes to 2 with a Gtk one.

### Dark theme: use StyleManager, not GtkSettings

Setting `gtk-application-prefer-dark-theme` warns and does nothing under
libadwaita. The colour scheme is Adwaita's to decide:

```ruby
# WRONG - warns "Using GtkSettings:gtk-application-prefer-dark-theme
#         with libadwaita is unsupported"
Gtk::Settings.default.gtk_application_prefer_dark_theme = true

# RIGHT
Adwaita::StyleManager.default.color_scheme =
  dark ? Adwaita::ColorScheme::FORCE_DARK : Adwaita::ColorScheme::DEFAULT
```

`Adwaita::ColorScheme` provides `DEFAULT`, `FORCE_DARK`, `FORCE_LIGHT`,
`PREFER_DARK` and `PREFER_LIGHT`. Use `DEFAULT` rather than `FORCE_LIGHT` to
turn a dark preference back off, so the desktop's own setting is followed
again.

---

## 6. Working Adwaita App Pattern

Complete pattern that works with Ruby bindings:

```ruby
require 'adwaita'

class MyApp
  def build
    app.tap do |a|
      a.signal_connect('activate') do
        # AdwApplicationWindow registers itself with the application.
        window.tap do |win|
          win.title = 'My App'
          win.set_default_size(800, 600)
          # AdwApplicationWindow takes `content`, not `child`.
          win.content = toast_overlay

          toast_overlay.tap do |to|
            to.child = split_view

            split_view.tap do |sv|
              sv.sidebar = sidebar_page
              sv.content = content_page

              # Configure sidebar_page contents via sidebar_toolbar
              sidebar_toolbar.tap do |st|
                st.add_top_bar(left_header)
                st.content = list_widget
              end

              # Configure content_page contents via content_toolbar
              content_toolbar.tap do |ct|
                ct.add_top_bar(right_header)
                ct.content = detail_widget
              end
            end
          end
        end

        window.present
      end
    end
  end

  def run = app.run([])

  # Adwaita::Application is still broken, so the application object is a Gtk
  # one. Adwaita::ApplicationWindow works as of 4.3.8, and using it is what
  # keeps Adwaita::Dialog inside the window instead of spawning a toplevel.
  def app = @app ||= Gtk::Application.new('org.example.myapp', :default_flags)
  def window = @window ||= Adwaita::ApplicationWindow.new(app)

  # Adwaita widgets that work
  def toast_overlay = @toast_overlay ||= Adwaita::ToastOverlay.new

  def split_view
    @split_view ||= Adwaita::NavigationSplitView.new.tap do |sv|
      sv.sidebar_width_fraction = 0.3
      sv.min_sidebar_width = 260
      sv.max_sidebar_width = 360
    end
  end

  # NavigationPage - positional args required, child first
  def sidebar_page
    @sidebar_page ||= Adwaita::NavigationPage.new(sidebar_toolbar, 'Sidebar')
  end

  def content_page
    @content_page ||= Adwaita::NavigationPage.new(content_toolbar, 'Content')
  end

  def sidebar_toolbar = @sidebar_toolbar ||= Adwaita::ToolbarView.new
  def content_toolbar = @content_toolbar ||= Adwaita::ToolbarView.new
  def left_header = @left_header ||= Adwaita::HeaderBar.new
  def right_header = @right_header ||= Adwaita::HeaderBar.new

  def list_widget = @list_widget ||= Gtk::Label.new('List goes here')
  def detail_widget = @detail_widget ||= Gtk::Label.new('Details go here')
end

MyApp.new.build.run
```

---

## Summary Table

| Widget | Constructor | Notes |
|--------|-------------|-------|
| `Adwaita::Application` | BROKEN | Use `Gtk::Application` |
| `Adwaita::ApplicationWindow` | `.new(gtk_app)` | Works since 4.3.8; takes `content=`, keeps dialogs in-window |
| `Adwaita::NavigationPage` | `.new(child, title)` | Positional args only |
| `Adwaita::NavigationSplitView` | `.new` | Works normally |
| `Adwaita::ToolbarView` | `.new` | Works normally |
| `Adwaita::HeaderBar` | `.new` | Works normally |
| `Adwaita::ToastOverlay` | `.new` | Works normally |
| `Adwaita::Toast` | `.new(message)` | Message required |
| `Adwaita::StatusPage` | `.new` | Works normally |
| `Adwaita::Clamp` | `.new` | Works normally |
| `Adwaita::Bin` | `.new` | Works normally |
| `Adwaita::Avatar` | `.new(size, text, show_initials)` | Positional args |
| `Adwaita::PreferencesGroup` | `.new` | Use `add()` for rows |
| `Adwaita::PreferencesRow` | `.new` | Set `child` manually |
| `Adwaita::ActionRow` | `.new` | Works normally |
| `Adwaita::EntryRow` | `.new` | Works normally |
| `Adwaita::PasswordEntryRow` | `.new` | Works normally |
| `Adwaita::SwitchRow` | `.new` | Works normally; read state with `active?` |
| `Adwaita::ComboRow` | `.new` | `model=` a `Gtk::StringList`, `selected` is an index |
| `Adwaita::ExpanderRow` | `.new` | Works normally |
| `Adwaita::SpinRow` | needs args | `.new` with no args raises; read the error for the signature |
| `Adwaita::Dialog` | `.new` | `present(parent)`; in-window only under an Adwaita window |
| `Adwaita::AlertDialog` | `.new` | Works normally; `add_response` / `choose` |
| `Adwaita::PreferencesDialog` | `.new` | Works normally; `add()` takes pages |
| `Adwaita::PreferencesPage` | `.new` | Works normally; `add()` takes groups |
| `Adwaita::WindowTitle` | `.new(title, subtitle)` | Positional args |
| `Adwaita::ButtonContent` | `.new` | Works normally |
| `Adwaita::StyleManager` | `.default` | Singleton; set `color_scheme` for dark mode |

---

## Adding New Widgets

When you encounter a new Adwaita widget:

1. Try `.new` with no arguments first
2. If that fails, read the error message for required signatures
3. Try positional arguments in the order shown
4. If keyword arguments are shown, try them but expect failure
5. Document the working pattern here
