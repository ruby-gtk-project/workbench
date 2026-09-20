# Ruby GTK4 Declarative Patterns Guide â€” Additions

This document contains additional patterns and rules discovered through building a complete contacts application.

---

## Table of Contents

1. [Style Placement Rule](#1-style-placement-rule)
2. [Append Order Rule](#2-append-order-rule)
3. [Single-Line Memoized Methods](#3-single-line-memoized-methods)
4. [No Return Statements](#4-no-return-statements)
5. [No Local Variables â€” Use tap](#5-no-local-variables--use-tap)
6. [Method Chaining Over Multiple Statements](#6-method-chaining-over-multiple-statements)
7. [The .then + if Pattern](#7-the-then--if-pattern)
8. [Nesting Rule](#8-nesting-rule)
9. [Keep Data Models Simple](#9-keep-data-models-simple)
10. [Display All Fields Unconditionally](#10-display-all-fields-unconditionally)
11. [Class Extraction Criteria](#11-class-extraction-criteria)
12. [Incremental Development Rule](#12-incremental-development-rule)
13. [Backend Abstraction Pattern](#13-backend-abstraction-pattern)
14. [ListModel Chain Pattern](#14-listmodel-chain-pattern)
15. [SignalListItemFactory Pattern](#15-signallistitemfactory-pattern)
16. [Delete with Undo Pattern](#16-delete-with-undo-pattern)
17. [Entry Point Pattern](#17-entry-point-pattern)

---

## 1. Style Placement Rule

**Margins and styles belong in memoized methods, NOT in the build function.**

The build function should only contain functional calls (append, child=, signal_connect). All styling (margins, CSS classes, alignments) goes in the memoized method's tap block.

```ruby
# âŒ WRONG - styles in build
def build
  header_box.tap do |hb|
    hb.margin_top = 24      # Style in build
    hb.append(avatar_frame)
  end
end

def header_box = @header_box ||= Gtk::Box.new(:vertical, 12)
```

```ruby
# âœ… RIGHT - styles in memoized method
def build
  header_box.tap do |hb|
    hb.append(avatar_frame)  # Only functional calls
  end
end

def header_box
  @header_box ||= Gtk::Box.new(:vertical, 12).tap do |hb|
    hb.margin_top = 24       # Style in memoized method
  end
end
```

**Rationale:** This separates concerns â€” the build method describes structure and behavior, while memoized methods define what each widget *is* (including its appearance).

---

## 2. Append Order Rule

**Append widgets from INSIDE the parent's tap block, not before it.**

```ruby
# âŒ WRONG - appends before tap
box.append(label)
box.append(button)
box.tap do |b|
  # configuration...
end
```

```ruby
# âœ… RIGHT - appends inside tap
box.tap do |b|
  b.append(label)
  b.append(button)
end
```

**Rationale:** Keeps the declarative hierarchy clear â€” everything related to a widget happens inside its tap block.

---

## 3. Single-Line Memoized Methods

**If a memoized method needs no styling, keep it on one line. Multi-line ONLY when tap block has styling.**

```ruby
# Single line - no styling needed
def frame = @frame ||= Gtk::Frame.new
def stack = @stack ||= Gtk::Stack.new
def separator = @separator ||= Gtk::Separator.new(:horizontal)
def header = @header ||= ContactPaneHeader.new

# Multi-line - ONLY when tap block has styling
def header_box
  @header_box ||= Gtk::Box.new(:vertical, 12).tap do |hb|
    hb.margin_top = 24
    hb.margin_bottom = 24
  end
end
```

**Rationale:** Reduces visual noise. Single-line definitions are scannable; multi-line signals "there's configuration here."

---

## 4. No Return Statements

**Use `.then` with conditional blocks instead of guard clauses with `return`.**

```ruby
# âŒ WRONG - imperative guard with return
def show_edit_dialog
  contact = @store.selected_contact
  return unless contact

  editor = ContactEditor.new(contact: contact, ...)
  editor.build
  editor.present(window)
end
```

```ruby
# âœ… RIGHT - functional with .then
def show_edit_dialog
  @store.selected_contact.then do |contact|
    if contact
      ContactEditor.new(contact: contact, ...).tap do |editor|
        editor.build
        editor.present(window)
      end
    end
  end
end
```

**Rationale:** `return` is imperative control flow. `.then` with conditionals is declarative â€” it describes structure rather than jumping around.

---

## 5. No Local Variables â€” Use tap

**Don't assign to local variables. Use `tap` for object configuration.**

```ruby
# âŒ WRONG - local variable
def show_add_dialog
  editor = ContactEditor.new(...)
  editor.build
  editor.present(window)
end
```

```ruby
# âœ… RIGHT - tap block
def show_add_dialog
  ContactEditor.new(...).tap do |editor|
    editor.build
    editor.present(window)
  end
end
```

**Rationale:** Local variables fragment the flow. With `tap`, object creation and configuration is one cohesive expression. The variable only exists within its configuration scope.

---

## 6. Method Chaining Over Multiple Statements

**Compose operations as single expressions.**

```ruby
# âŒ WRONG - multiple statements
def add_contact(data)
  contact = @store.add_contact(**data)
  @store.select_contact(contact)
end
```

```ruby
# âœ… RIGHT - single expression
def add_contact(data)
  @store.select_contact(@store.add_contact(**data))
end
```

**Rationale:** The operation is: add â†’ select. The code should read that way. Data flows through the expression.

---

## 7. The .then + if Pattern

**Standard pattern for "do something with an optional value":**

```ruby
def operate_on_selected
  @store.selected_contact.then do |contact|
    if contact
      # work with contact
    end
  end
end
```

This replaces the imperative pattern:

```ruby
# âŒ WRONG
def operate_on_selected
  contact = @store.selected_contact
  return unless contact
  # work with contact
end
```

**When to use:**
- Any method that operates on a potentially-nil value
- Callback handlers where the subject might not exist
- Any place you'd write `return unless x`

---

## 8. Nesting Rule

**All widget configuration belongs inside the tap block of its parent.**

Controllers, signal handlers, and child additions should all be nested within the widget they belong to:

```ruby
def build
  window.tap do |win|
    win.title = 'App'
    win.child = box

    # âœ… Controller belongs to window, configured inside window's tap
    key_controller.tap do |kc|
      kc.signal_connect('key-pressed') do |_, keyval, _, state|
        handle_key(keyval, state)
      end
    end
    win.add_controller(key_controller)

    box.tap do |b|
      b.append(button)

      button.tap do |btn|
        btn.label = 'Click'
        # âœ… Signal belongs to button, inside button's tap
        btn.signal_connect('clicked') { on_click }
      end
    end
  end
end
```

**Rationale:** The build method reads as a single declarative tree structure. You can see the widget hierarchy by looking at the nesting.

---

## 9. Keep Data Models Simple

**Start with simple string attributes. Don't over-engineer until actually needed.**

```ruby
# âœ… START HERE - simple and working
class Contact < GLib::Object
  type_register
  attr_accessor :id, :name, :email, :phone
end
```

```ruby
# âŒ DON'T jump to this prematurely
class Contact < GLib::Object
  type_register
  attr_accessor :id, :name, :emails, :phones  # Arrays of value objects
  attr_accessor :addresses, :urls, :roles, :notes, :birthday
end
```

**Rationale:** Complexity should be earned. Start simple, add fields when you have actual use cases. Over-engineering data models creates cascading complexity in every layer that touches them.

---

## 10. Display All Fields Unconditionally

**Don't hide UI elements based on empty values. Show the field, let it be empty.**

```ruby
# âŒ WRONG - hiding rows based on data
def show_contact(contact)
  email_value.label = contact.email
  email_row.visible = !contact.email.empty?
end
```

```ruby
# âœ… RIGHT - always show the row
def show_contact(contact)
  email_value.label = contact.email
end
```

**Rationale:** Conditional visibility adds complexity and can cause layout shifts. An empty field is informative â€” it shows the user what data *could* be there.

---

## 11. Class Extraction Criteria

**Extract a new class when:**

- A component has more than ~10 widget methods
- There's a clear logical grouping (header vs details vs actions)
- The component could be reused
- Complex state management is needed

**Each extracted class follows the same pattern:**

```ruby
class ContactPaneHeader
  def build
    container.tap do |c|
      c.append(avatar_frame)
      c.append(name_label)

      avatar_frame.tap do |af|
        af.child = avatar_label
      end
    end
  end

  def update(contact)
    name_label.label = contact.display_name
    avatar_label.label = contact.initials
  end

  # Memoized widget methods...
  def container
    @container ||= Gtk::Box.new(:vertical, 12).tap do |c|
      c.margin_top = 24
    end
  end

  def avatar_frame = @avatar_frame ||= Gtk::Frame.new
  def avatar_label = @avatar_label ||= Gtk::Label.new
  def name_label = @name_label ||= Gtk::Label.new
end
```

**Pattern elements:**
- Constructor with callbacks (if needed)
- `build` method returns the root widget
- `update(data)` method to refresh display
- Memoized widget methods at bottom

---

## 12. Incremental Development Rule

**Never remove working functionality when adding features.**

1. Verify current features work
2. Add new features incrementally
3. Test that old features still work
4. Only then refactor if needed

**Anti-pattern:** Rewriting a component to add features, breaking existing functionality in the process.

---

## 13. Backend Abstraction Pattern

**Wrap persistence behind a simple interface:**

```ruby
module Backends
  class Backend
    def load           # â†’ Array<Hash>
      raise NotImplementedError
    end

    def create(hash)   # â†’ Hash (with id)
      raise NotImplementedError
    end

    def update(hash)   # â†’ Hash
      raise NotImplementedError
    end

    def delete(id)     # â†’ Boolean
      raise NotImplementedError
    end

    def display_name   # â†’ String (for UI)
      raise NotImplementedError
    end

    def location       # â†’ String (file path or URI)
      raise NotImplementedError
    end
  end
end
```

**Implementations:**

```ruby
class JsonBackend < Backend
  def load
    # Read JSON file, return array of hashes
  end
end

class VCardBackend < Backend
  def load
    # Read .vcf files from directory, return array of hashes
  end
end
```

---

## 14. ListModel Chain Pattern

**Standard chain for filtered, sorted, selectable lists:**

```
ListStore â†’ FilterListModel â†’ SortListModel â†’ SingleSelection
    â†“              â†“                â†“              â†“
  data         filtering         sorting       selection
```

```ruby
def list_store
  @list_store ||= Gio::ListStore.new(Contact)
end

def contact_filter
  @contact_filter ||= Gtk::CustomFilter.new do |item|
    @query.empty? ||
      item.name.downcase.include?(@query) ||
      item.email.downcase.include?(@query)
  end
end

def filter_model
  @filter_model ||= Gtk::FilterListModel.new(list_store, contact_filter)
end

def selection_model
  @selection_model ||= Gtk::SingleSelection.new(filter_model)
end
```

**To trigger filter update:**

```ruby
@query = search_entry.text.downcase
contact_filter.changed(Gtk::FilterChange::DIFFERENT)
```

---

## 15. SignalListItemFactory Pattern

**For ListView/GridView item rendering:**

```ruby
def list_factory
  @list_factory ||= Gtk::SignalListItemFactory.new.tap do |f|
    f.signal_connect('setup') do |_, item|
      # Create widget structure (called once per visible row)
      item.child = Gtk::Box.new(:horizontal, 12).tap do |box|
        box.margin_top = 8
        box.margin_bottom = 8
        box.margin_start = 12
        box.margin_end = 12
        box.append(Gtk::Frame.new.tap do |frame|
          frame.add_css_class('circular')
          frame.child = Gtk::Label.new.tap { |l| l.set_size_request(32, 32) }
        end)
        box.append(Gtk::Label.new.tap { |l| l.xalign = 0; l.hexpand = true })
      end
    end

    f.signal_connect('bind') do |_, item|
      # Populate with data (called when data changes)
      contact = item.item
      box = item.child
      avatar_frame = box.first_child
      name_label = avatar_frame.next_sibling

      avatar_frame.child.label = contact.initials
      name_label.label = contact.display_name
    end
  end
end
```

**Key points:**
- `setup` creates the widget structure once
- `bind` populates with data (may be called multiple times)
- Navigate widget tree with `first_child`, `next_sibling`

---

## 16. Delete with Undo Pattern

```ruby
def delete_selected_contact
  @store.selected_contact.then do |contact|
    if contact
      @deleted_undo_info = @store.delete_contact(contact)
      contact_pane.show_contact(nil)

      info_bar_label.label = "Deleted #{contact.display_name}"
      info_bar.revealed = true

      # Auto-hide after 5 seconds
      GLib::Timeout.add_seconds(5) do
        if info_bar.revealed?
          info_bar.revealed = false
          @deleted_undo_info = nil
        end
        false  # Don't repeat the timeout
      end
    end
  end
end

def handle_undo(response_id)
  if response_id == 1 && @deleted_undo_info
    @store.select_contact(@store.restore_contact(@deleted_undo_info))
  end
  info_bar.revealed = false
  @deleted_undo_info = nil
end
```

**Store methods:**

```ruby
def delete_contact(contact)
  position = find_position(contact)
  @backend.delete(contact.id)
  @list_store.remove(position)
  { position: position, contact: contact }  # Undo info
end

def restore_contact(undo_info)
  contact = undo_info[:contact]
  position = undo_info[:position]
  @backend.create(contact.to_h)
  @list_store.insert(position, contact)
  contact
end
```

---

## 17. Entry Point Pattern

**Applications start with a single expression:**

```ruby
ContactsApp.new.build.run
```

Or with configuration:

```ruby
if __FILE__ == $PROGRAM_NAME
  backend = case ARGV[0]&.to_sym
            when :vcard then Backends::VCardBackend.new
            else Backends::JsonBackend.new
            end

  puts "Using backend: #{backend.display_name}"
  puts "Data location: #{backend.location}"

  ContactsApp.new(backend: backend).build.run
end
```

**The pattern:**
- `new` â€” instantiate with dependencies
- `build` â€” wire up the UI (returns `app` for chaining)
- `run` â€” start the GTK main loop

---

## Summary Table

| Rule | Wrong | Right |
|------|-------|-------|
| Styles | In build method | In memoized method tap block |
| Appends | Before parent's tap | Inside parent's tap |
| Simple memoized | Multi-line | Single line |
| Guard clauses | `return unless x` | `.then { \|x\| if x }` |
| Object config | Local variable | `.tap { \|x\| }` |
| Multi-step ops | Separate statements | Method chaining |
| Optional values | `return unless` | `.then + if` |
| Widget config | Outside parent | Nested in parent's tap |
| Data models | Complex from start | Simple, add as needed |
| Empty fields | Hide with visibility | Always show |
