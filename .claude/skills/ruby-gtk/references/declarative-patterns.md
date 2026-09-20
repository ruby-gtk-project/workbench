# Ruby GTK4 Declarative Patterns Guide

A comprehensive guide to writing idiomatic, maintainable GTK4 applications in Ruby using declarative patterns inspired by Sandi Metz's principles.

---

## Table of Contents

1. [Philosophy](#philosophy)
2. [Core Principles](#core-principles)
3. [The Pattern](#the-pattern)
4. [Basic Examples](#basic-examples)
5. [Signal Handling](#signal-handling)
6. [List Factories](#list-factories)
7. [Custom Drawing](#custom-drawing)
8. [Scaling to Complexity](#scaling-to-complexity)
9. [Common GTK4 Ruby Patterns](#common-gtk4-ruby-patterns)
10. [Quick Reference](#quick-reference)

---

## Philosophy

This guide blends Ruby's functional and object-oriented strengths to create GTK4 applications that are:

- **Declarative**: Widgets are defined as what they are, not how to build them
- **Lazy**: Components are created only when first accessed
- **Composable**: Small, focused methods combine into complex UIs
- **Maintainable**: Following Sandi Metz's principles for sustainable code

### Key Influences

- **Sandi Metz**: Small methods, single responsibility, dependency injection
- **Functional Ruby**: Memoization, lazy evaluation, immutable-style thinking
- **GTK4 Architecture**: Signal-based reactivity, widget composition

---

## Core Principles

### 1. Components as Memoized Methods

Every widget is a method that returns a memoized instance:

```ruby
def button = @button ||= Gtk::Button.new
def label = @label ||= Gtk::Label.new
def box = @box ||= Gtk::Box.new(:vertical, 8)
```

### 2. Configuration in `tap` Blocks

All widget configuration happens inside `tap` blocks within the `build` method:

```ruby
def build
  window.tap do |win|
    win.title = 'My App'
    win.set_default_size(400, 300)
    win.child = box
  end
end
```

### 3. Dependencies via Method Calls

Components reference each other through method calls, not instance variables:

```ruby
# Good: method call
box.append(button)

# Avoid: storing in variables during construction
@my_button = Gtk::Button.new
box.append(@my_button)
```

### 4. Assembly in `build` Method

The `build` method is the single assembly point that wires everything together:

```ruby
def build
  app.tap do
    app.signal_connect('activate') do
      # All wiring happens here
    end
  end
end
```

### 5. Single Expression Entry Point

Applications start with a single expression:

```ruby
MyApp.new.build.run
```

---

## The Pattern

### Minimal Template

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
          win.child = content
        end

        # Configure all components here

        window.present
      end
    end
  end

  def app = @app ||= Gtk::Application.new('org.example.myapp', :default_flags)
  def window = @window ||= Gtk::Window.new
  def content = @content ||= Gtk::Label.new('Hello, World!')
end

MyApp.new.build.run
```

### Structure Explanation

```
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚  build method                                       â”‚
â”‚  â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”  â”‚
â”‚  â”‚  app.tap do                                   â”‚  â”‚
â”‚  â”‚    signal_connect('activate') do              â”‚  â”‚
â”‚  â”‚      â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”  â”‚  â”‚
â”‚  â”‚      â”‚  window.tap { configure... }        â”‚  â”‚  â”‚
â”‚  â”‚      â”‚  component.tap { configure... }     â”‚  â”‚  â”‚
â”‚  â”‚      â”‚  widget.tap { configure... }        â”‚  â”‚  â”‚
â”‚  â”‚      â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜  â”‚  â”‚
â”‚  â”‚    end                                        â”‚  â”‚
â”‚  â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜  â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜

â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚  Component Methods (memoized, at bottom of class)   â”‚
â”‚                                                     â”‚
â”‚  def app = @app ||= Gtk::Application.new(...)       â”‚
â”‚  def window = @window ||= Gtk::Window.new           â”‚
â”‚  def box = @box ||= Gtk::Box.new(:vertical, 8)      â”‚
â”‚  def button = @button ||= Gtk::Button.new           â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
```

---

## Basic Examples

### Counter Application

```ruby
require 'gtk4'

class CounterApp
  def build
    app.tap do
      app.signal_connect('activate') do
        app.add_window(window)

        window.tap do |win|
          win.title = 'Counter'
          win.set_default_size(200, 100)
          win.child = box
        end

        box.tap do |b|
          b.margin_top = 20
          b.margin_bottom = 20
          b.margin_start = 20
          b.margin_end = 20
          b.append(label)
          b.append(button)
        end

        label.tap do |l|
          l.label = count.to_s
          l.add_css_class('title-1')
        end

        button.tap do |btn|
          btn.label = 'Increment'
          btn.signal_connect('clicked') do
            @count = count + 1
            label.label = count.to_s
          end
        end

        window.present
      end
    end
  end

  def app = @app ||= Gtk::Application.new('org.example.counter', :default_flags)
  def window = @window ||= Gtk::Window.new
  def box = @box ||= Gtk::Box.new(:vertical, 12)
  def label = @label ||= Gtk::Label.new
  def button = @button ||= Gtk::Button.new
  def count = @count ||= 0
end

CounterApp.new.build.run
```

### Form with Multiple Inputs

```ruby
require 'gtk4'

class FormApp
  def build
    app.tap do
      app.signal_connect('activate') do
        app.add_window(window)

        window.tap do |win|
          win.title = 'User Form'
          win.set_default_size(300, 200)
          win.child = grid
        end

        grid.tap do |g|
          g.row_spacing = 8
          g.column_spacing = 12
          g.margin_top = 16
          g.margin_bottom = 16
          g.margin_start = 16
          g.margin_end = 16

          g.attach(name_label, 0, 0, 1, 1)
          g.attach(name_entry, 1, 0, 1, 1)
          g.attach(email_label, 0, 1, 1, 1)
          g.attach(email_entry, 1, 1, 1, 1)
          g.attach(submit_button, 1, 2, 1, 1)
        end

        name_label.tap { |l| l.label = 'Name:'; l.xalign = 0 }
        email_label.tap { |l| l.label = 'Email:'; l.xalign = 0 }

        name_entry.tap { |e| e.hexpand = true }
        email_entry.tap { |e| e.hexpand = true }

        submit_button.tap do |btn|
          btn.label = 'Submit'
          btn.add_css_class('suggested-action')
          btn.signal_connect('clicked') do
            puts "Name: #{name_entry.text}"
            puts "Email: #{email_entry.text}"
          end
        end

        window.present
      end
    end
  end

  def app = @app ||= Gtk::Application.new('org.example.form', :default_flags)
  def window = @window ||= Gtk::Window.new
  def grid = @grid ||= Gtk::Grid.new
  def name_label = @name_label ||= Gtk::Label.new
  def name_entry = @name_entry ||= Gtk::Entry.new
  def email_label = @email_label ||= Gtk::Label.new
  def email_entry = @email_entry ||= Gtk::Entry.new
  def submit_button = @submit_button ||= Gtk::Button.new
end

FormApp.new.build.run
```

---

## Signal Handling

### Basic Signals

```ruby
button.tap do |btn|
  btn.signal_connect('clicked') { puts 'Clicked!' }
end
```

### Signals with Parameters

```ruby
entry.tap do |e|
  e.signal_connect('changed') { puts "Text: #{e.text}" }
  e.signal_connect('activate') { puts 'Enter pressed' }
end
```

### Property Notifications

```ruby
dropdown.tap do |dd|
  dd.signal_connect('notify::selected') do
    puts "Selected index: #{dd.selected}"
  end
end
```

### State Flags for Hover/Selection

```ruby
widget.tap do |w|
  w.signal_connect('state-flags-changed') do
    flags = w.state_flags
    if flags.prelight? || flags.selected?
      extra_buttons.visible = true
    else
      extra_buttons.visible = false
    end
  end
end
```

### Gesture Controllers

```ruby
# Drag gesture
drag_gesture.tap do |drag|
  drag.signal_connect('drag-begin') { |_, x, y| on_drag_begin(x, y) }
  drag.signal_connect('drag-update') { |_, dx, dy| on_drag_update(dx, dy) }
  drag.signal_connect('drag-end') { |_, dx, dy| on_drag_end(dx, dy) }
end

drawing_area.add_controller(drag_gesture)

# Click gesture
click_gesture.tap do |click|
  click.button = 3  # Right-click
  click.signal_connect('pressed') { |_, n, x, y| on_right_click(x, y) }
end

widget.add_controller(click_gesture)
```

---

## List Factories

### SignalListItemFactory Pattern

GTK4 uses factories to create list item widgets. The `SignalListItemFactory` provides Ruby-friendly callbacks:

```ruby
def list_factory
  @list_factory ||= Gtk::SignalListItemFactory.new.tap do |f|
    f.signal_connect('setup') do |_, item|
      # Create widget structure (called once per visible row)
      item.child = Gtk::Box.new(:horizontal, 8).tap do |box|
        box.append(Gtk::Image.new)
        box.append(Gtk::Label.new)
      end
    end

    f.signal_connect('bind') do |_, item|
      # Populate with data (called when data changes)
      data = item.item  # The actual data object
      box = item.child
      image = box.first_child
      label = image.next_sibling

      image.icon_name = data.icon
      label.label = data.name
    end
  end
end
```

### Complete ListView Example

```ruby
require 'gtk4'

class ListViewDemo
  Item = Data.define(:name, :icon)

  def build
    app.tap do
      app.signal_connect('activate') do
        app.add_window(window)

        window.tap do |win|
          win.title = 'List View'
          win.set_default_size(300, 400)
          win.child = scrolled_window
        end

        scrolled_window.tap do |sw|
          sw.child = list_view
        end

        list_view.tap do |lv|
          lv.model = selection_model
          lv.factory = list_factory
          lv.signal_connect('activate') do |_, pos|
            item = selection_model.get_item(pos)
            puts "Activated: #{item.name}"
          end
        end

        window.present
      end
    end
  end

  def app = @app ||= Gtk::Application.new('org.example.listview', :default_flags)
  def window = @window ||= Gtk::Window.new
  def scrolled_window = @scrolled_window ||= Gtk::ScrolledWindow.new
  def list_view = @list_view ||= Gtk::ListView.new

  def items
    @items ||= [
      Item.new(name: 'Documents', icon: 'folder-documents-symbolic'),
      Item.new(name: 'Music', icon: 'folder-music-symbolic'),
      Item.new(name: 'Pictures', icon: 'folder-pictures-symbolic'),
      Item.new(name: 'Videos', icon: 'folder-videos-symbolic')
    ]
  end

  def list_store
    @list_store ||= Gio::ListStore.new(Item).tap do |store|
      items.each { |item| store.append(item) }
    end
  end

  def selection_model
    @selection_model ||= Gtk::SingleSelection.new(list_store)
  end

  def list_factory
    @list_factory ||= Gtk::SignalListItemFactory.new.tap do |f|
      f.signal_connect('setup') do |_, item|
        item.child = Gtk::Box.new(:horizontal, 12).tap do |box|
          box.margin_start = 8
          box.margin_end = 8
          box.margin_top = 4
          box.margin_bottom = 4
          box.append(Gtk::Image.new)
          box.append(Gtk::Label.new.tap { |l| l.hexpand = true; l.xalign = 0 })
        end
      end

      f.signal_connect('bind') do |_, item|
        data = item.item
        box = item.child
        image = box.first_child
        label = image.next_sibling

        image.icon_name = data.icon
        label.label = data.name
      end
    end
  end
end

ListViewDemo.new.build.run
```

### Multiple Factory Definitions (View Switcher)

```ruby
def views
  @views ||= [
    {
      icon_name: 'view-list-symbolic',
      title: 'List',
      orientation: :horizontal,
      factory: list_factory
    },
    {
      icon_name: 'view-grid-symbolic',
      title: 'Grid',
      orientation: :vertical,
      factory: grid_factory
    }
  ]
end

def list_factory
  @list_factory ||= Gtk::SignalListItemFactory.new.tap do |f|
    f.signal_connect('setup') do |_, item|
      item.child = Gtk::Box.new(:horizontal, 6).tap do |box|
        box.append(Gtk::Image.new)
        box.append(Gtk::Label.new.tap { |l| l.halign = :start })
      end
    end

    f.signal_connect('bind') do |_, item|
      info = item.item
      box = item.child
      image = box.first_child
      label = image.next_sibling

      image.gicon = info.icon
      label.label = info.display_name
    end
  end
end

def grid_factory
  @grid_factory ||= Gtk::SignalListItemFactory.new.tap do |f|
    f.signal_connect('setup') do |_, item|
      item.child = Gtk::Box.new(:vertical, 6).tap do |box|
        box.append(Gtk::Image.new.tap { |i| i.icon_size = :large })
        box.append(Gtk::Label.new.tap do |l|
          l.wrap = true
          l.lines = 2
          l.ellipsize = :end
        end)
      end
    end

    f.signal_connect('bind') do |_, item|
      info = item.item
      box = item.child
      image = box.first_child
      label = image.next_sibling

      image.gicon = info.icon
      label.label = info.display_name
    end
  end
end
```

---

## Custom Drawing

### Drawing Area with Cairo

```ruby
require 'gtk4'

class DrawingDemo
  def build
    app.tap do
      app.signal_connect('activate') do
        app.add_window(window)

        window.tap do |win|
          win.title = 'Drawing'
          win.set_default_size(400, 300)
          win.child = drawing_area
        end

        drawing_area.tap do |da|
          da.set_draw_func { |_, cr, w, h| draw(cr, w, h) }
        end

        window.present
      end
    end
  end

  def app = @app ||= Gtk::Application.new('org.example.drawing', :default_flags)
  def window = @window ||= Gtk::Window.new
  def drawing_area = @drawing_area ||= Gtk::DrawingArea.new

  private

  def draw(cr, width, height)
    # Background
    cr.set_source_rgb(0.2, 0.2, 0.2)
    cr.paint

    # Circle
    cr.set_source_rgb(0.8, 0.2, 0.2)
    cr.arc(width / 2, height / 2, 50, 0, 2 * Math::PI)
    cr.fill

    # Text
    cr.set_source_rgb(1, 1, 1)
    cr.select_font_face("Sans", Cairo::FontSlant::NORMAL, Cairo::FontWeight::BOLD)
    cr.set_font_size(20)
    cr.move_to(10, 30)
    cr.show_text("Hello Cairo!")
  end
end

DrawingDemo.new.build.run
```

### Interactive Drawing with Drag

```ruby
class InteractiveDrawing
  def build
    app.tap do
      app.signal_connect('activate') do
        app.add_window(window)

        window.tap do |win|
          win.title = 'Interactive Drawing'
          win.set_default_size(400, 300)
          win.child = drawing_area
        end

        drawing_area.tap do |da|
          da.set_draw_func { |_, cr, w, h| draw(cr, w, h) }
          da.add_controller(drag_gesture)
        end

        drag_gesture.tap do |drag|
          drag.signal_connect('drag-begin') { |_, x, y| on_drag_begin(x, y) }
          drag.signal_connect('drag-update') { |_, dx, dy| on_drag_update(dx, dy) }
        end

        window.present
      end
    end
  end

  def app = @app ||= Gtk::Application.new('org.example.interactive', :default_flags)
  def window = @window ||= Gtk::Window.new
  def drawing_area = @drawing_area ||= Gtk::DrawingArea.new
  def drag_gesture = @drag_gesture ||= Gtk::GestureDrag.new

  def circle_x = @circle_x ||= 200
  def circle_y = @circle_y ||= 150

  private

  def draw(cr, width, height)
    cr.set_source_rgb(0.15, 0.15, 0.15)
    cr.paint

    cr.set_source_rgb(0.4, 0.6, 0.8)
    cr.arc(circle_x, circle_y, 40, 0, 2 * Math::PI)
    cr.fill
  end

  def on_drag_begin(x, y)
    @drag_start_x = circle_x
    @drag_start_y = circle_y
  end

  def on_drag_update(dx, dy)
    @circle_x = @drag_start_x + dx
    @circle_y = @drag_start_y + dy
    drawing_area.queue_draw
  end
end

InteractiveDrawing.new.build.run
```

---

## Scaling to Complexity

### When to Extract Classes

Extract a new class when:

- A component has more than 10 widget methods
- Complex state management is needed
- The component is reusable
- There's a clear logical grouping

### Multi-Class Pattern

Each extracted class follows the same pattern with its own `build` method:

```ruby
class MonitorCard
  def initialize(monitor:, on_change:)
    @monitor = monitor
    @on_change = on_change
  end

  def build
    @build ||= Gtk::Frame.new.tap do |frame|
      frame.label = @monitor.name
      frame.child = grid

      grid.tap do |g|
        g.row_spacing = 8
        g.column_spacing = 12
        g.attach(resolution_label, 0, 0, 1, 1)
        g.attach(resolution_combo, 1, 0, 1, 1)
      end

      resolution_label.tap { |l| l.label = 'Resolution:'; l.xalign = 0 }

      resolution_combo.tap do |c|
        c.model = Gtk::StringList.new(@monitor.resolutions)
        c.signal_connect('notify::selected') { @on_change.call }
      end
    end
  end

  def grid = @grid ||= Gtk::Grid.new
  def resolution_label = @resolution_label ||= Gtk::Label.new
  def resolution_combo = @resolution_combo ||= Gtk::DropDown.new

  def selected_resolution
    @monitor.resolutions[resolution_combo.selected]
  end
end

class MonitorApp
  def build
    app.tap do
      app.signal_connect('activate') do
        app.add_window(window)

        window.tap do |win|
          win.child = box
        end

        box.tap do |b|
          cards.each { |card| b.append(card.build) }
        end

        window.present
      end
    end
  end

  def app = @app ||= Gtk::Application.new('org.example.monitors', :default_flags)
  def window = @window ||= Gtk::Window.new
  def box = @box ||= Gtk::Box.new(:vertical, 8)

  def monitors = @monitors ||= load_monitors
  def cards
    @cards ||= monitors.map do |monitor|
      MonitorCard.new(monitor: monitor, on_change: -> { update_display })
    end
  end

  def update_display
    # React to card changes
  end
end
```

### Instance Tracking Pattern

When GTK widgets need to reference Ruby objects:

```ruby
def message_rows = @message_rows ||= {}

# In build, store the mapping
messages.each do |message|
  msg_row = MessageRow.new(message)
  gtk_row = Gtk::ListBoxRow.new
  gtk_row.child = msg_row.build
  message_rows[gtk_row] = msg_row  # Track the association
  list_box.append(gtk_row)
end

# In signal handler, retrieve the Ruby object
list_box.signal_connect('row-activated') do |_, row|
  message_rows[row]&.toggle_expand
end
```

---

## Common GTK4 Ruby Patterns

### Window Setup

```ruby
window.tap do |win|
  win.title = 'App Name'
  win.set_default_size(800, 600)  # Note: two arguments, not array
  win.titlebar = header_bar       # Custom titlebar
  win.child = content
end
```

### Margins and Spacing

```ruby
box.tap do |b|
  b.margin_top = 16
  b.margin_bottom = 16
  b.margin_start = 16
  b.margin_end = 16
  b.spacing = 8  # Only for Box, not Grid
end

grid.tap do |g|
  g.row_spacing = 8
  g.column_spacing = 12
end
```

### CSS Classes

```ruby
button.add_css_class('suggested-action')  # Blue primary button
button.add_css_class('destructive-action')  # Red danger button
box.add_css_class('linked')  # Joined button group
label.add_css_class('dim-label')  # Subdued text
label.add_css_class('title-1')  # Large title
list_box.add_css_class('boxed-list')  # Rounded list style
```

### Pango Attributes

```ruby
label.tap do |l|
  l.use_markup = true
  l.label = '<b>Bold</b> and <i>italic</i>'
end

# Or programmatically:
label.attributes = Pango::AttrList.new.tap do |attrs|
  attrs.insert(Pango::AttrWeight.new(:bold))
end
```

### Menu Models

```ruby
def menu_model
  @menu_model ||= Gio::Menu.new.tap do |menu|
    section = Gio::Menu.new
    section.append('Copy', 'app.copy')
    section.append('Paste', 'app.paste')
    menu.append_section(nil, section)

    section2 = Gio::Menu.new
    section2.append('Settings', 'app.settings')
    menu.append_section(nil, section2)
  end
end

menu_button.tap do |btn|
  btn.menu_model = menu_model
  btn.icon_name = 'open-menu-symbolic'
end
```

### DropDown (Combo Box Replacement)

```ruby
dropdown.tap do |dd|
  dd.model = Gtk::StringList.new(['Option 1', 'Option 2', 'Option 3'])
  dd.selected = 0
  dd.signal_connect('notify::selected') do
    puts "Selected: #{dd.selected}"
  end
end
```

### Toggle Button Groups

```ruby
views.each_with_index do |view, i|
  Gtk::ToggleButton.new.tap do |btn|
    btn.icon_name = view[:icon_name]
    btn.active = i.zero?
    btn.group = @first_button unless i.zero?
    @first_button ||= btn

    btn.signal_connect('toggled') do
      apply_view(view) if btn.active?
    end

    button_box.append(btn)
  end
end
```

### Size Groups

```ruby
def label_size_group
  @label_size_group ||= Gtk::SizeGroup.new(:horizontal)
end

# Apply to labels to make them equal width
label1.tap { |l| label_size_group.add_widget(l) }
label2.tap { |l| label_size_group.add_widget(l) }
```

### Revealer (Expand/Collapse)

```ruby
revealer.tap do |r|
  r.transition_type = :slide_down
  r.reveal_child = false
  r.child = details_box
end

toggle_button.signal_connect('clicked') do
  revealer.reveal_child = !revealer.reveal_child
end
```

---

## Quick Reference

### Widget Creation Patterns

| Widget | Pattern |
|--------|---------|
| Application | `Gtk::Application.new('org.example.app', :default_flags)` |
| Window | `Gtk::Window.new` or `Gtk::ApplicationWindow.new(app)` |
| Box | `Gtk::Box.new(:vertical, spacing)` |
| Grid | `Gtk::Grid.new` |
| Button | `Gtk::Button.new` or `Gtk::Button.new(label: 'Text')` |
| Label | `Gtk::Label.new` or `Gtk::Label.new('text')` |
| Entry | `Gtk::Entry.new` |
| DropDown | `Gtk::DropDown.new` |
| ListView | `Gtk::ListView.new` |
| ListBox | `Gtk::ListBox.new` |
| ScrolledWindow | `Gtk::ScrolledWindow.new` |
| DrawingArea | `Gtk::DrawingArea.new` |
| Image | `Gtk::Image.new` |
| HeaderBar | `Gtk::HeaderBar.new` |
| Frame | `Gtk::Frame.new` |
| Revealer | `Gtk::Revealer.new` |
| Separator | `Gtk::Separator.new(:horizontal)` |

### Common Properties

| Property | Example |
|----------|---------|
| Child widget | `container.child = widget` |
| Append to Box | `box.append(widget)` |
| Grid attach | `grid.attach(widget, col, row, colspan, rowspan)` |
| Expand | `widget.hexpand = true` |
| Alignment | `widget.halign = :center` (`:start`, `:end`, `:fill`) |
| Visibility | `widget.visible = false` |
| Sensitivity | `widget.sensitive = false` |
| Size request | `widget.set_size_request(width, height)` |

### Signal Connection

```ruby
widget.signal_connect('signal-name') do |widget, *args|
  # Handler code
end
```

### Common Signals

| Widget | Signal | Parameters |
|--------|--------|------------|
| Button | `'clicked'` | none |
| Entry | `'changed'` | none |
| Entry | `'activate'` | none (Enter pressed) |
| DropDown | `'notify::selected'` | none |
| ListView | `'activate'` | position |
| ListBox | `'row-activated'` | row |
| Widget | `'state-flags-changed'` | none |
| GestureDrag | `'drag-begin'` | x, y |
| GestureDrag | `'drag-update'` | dx, dy |
| GestureDrag | `'drag-end'` | dx, dy |
| GestureClick | `'pressed'` | n_press, x, y |

### Enum Values

Use symbols for enum values:

```ruby
box.orientation = :vertical      # or :horizontal
label.halign = :start            # :end, :center, :fill
label.ellipsize = :end           # :start, :middle, :none
label.wrap_mode = :word_char     # :word, :char
revealer.transition_type = :slide_down  # :crossfade, :slide_up, etc.
```

### Data Classes

Use `Data.define` for simple data objects:

```ruby
Item = Data.define(:name, :icon, :count) do
  def display_name
    "#{name} (#{count})"
  end
end

item = Item.new(name: 'Test', icon: 'folder', count: 5)
```

---

## Summary

The declarative pattern for Ruby GTK4 applications:

1. **Memoize all widgets** as single-line methods at the bottom of the class
2. **Configure in `tap` blocks** within the `build` method
3. **Connect signals** inside the `tap` block of the relevant widget
4. **Reference components** via method calls, not instance variables
5. **Start with a single expression**: `MyApp.new.build.run`
6. **Extract classes** when complexity grows, each following the same pattern
7. **Track instances** with hashes when GTK widgets need Ruby object references

This approach produces code that is:

- Easy to read (widget definitions are declarations)
- Easy to modify (changes are localized)
- Easy to extend (add new memoized methods)
- Consistent (every class follows the same structure)
