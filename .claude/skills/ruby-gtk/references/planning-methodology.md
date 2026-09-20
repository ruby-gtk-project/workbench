# Planning and Building Data-Oriented Ruby GTK4 Applications

A step-by-step methodology for analyzing existing production apps and building Ruby equivalents using declarative patterns.

---

## Table of Contents

1. [Philosophy](#philosophy)
2. [Phase 1: Analysis](#phase-1-analysis)
3. [Phase 2: Architecture Mapping](#phase-2-architecture-mapping)
4. [Phase 3: Minimal Viable Implementation](#phase-3-minimal-viable-implementation)
5. [Phase 4: Incremental Feature Addition](#phase-4-incremental-feature-addition)
6. [Phase 5: Refinement](#phase-5-refinement)
7. [Common Pitfalls](#common-pitfalls)
8. [Case Study: Contacts App](#case-study-contacts-app)

---

## Philosophy

When building a data-oriented GTK4 application, the goal is to:

1. **Understand the existing architecture** before writing any code
2. **Identify what's essential** vs. what's over-engineered
3. **Start with the simplest possible working version**
4. **Add features incrementally** without breaking what works
5. **Follow consistent patterns** throughout

The key insight: Production apps often contain complexity that exists for historical reasons, edge cases, or framework constraints that don't apply to your implementation. Your job is to extract the essential architecture and rebuild it simply.

---

## Phase 1: Analysis

### Step 1.1: Directory Structure Analysis

Start by examining the file tree of the existing app. Look for patterns:

```
app/
â”œâ”€â”€ main.vala                    â†’ Entry point
â”œâ”€â”€ app.vala                     â†’ Application class
â”œâ”€â”€ main-window.vala             â†’ Main window
â”œâ”€â”€ store.vala                   â†’ Data layer
â”œâ”€â”€ contact.vala                 â†’ Data model
â”œâ”€â”€ contact-list.vala            â†’ List view
â”œâ”€â”€ contact-pane.vala            â†’ Detail view
â”œâ”€â”€ contact-editor.vala          â†’ Edit dialog
â”œâ”€â”€ core/                        â†’ Domain objects
â”‚   â”œâ”€â”€ chunk.vala               â†’ Field abstraction
â”‚   â””â”€â”€ *-chunk.vala             â†’ Specific field types
â”œâ”€â”€ io/                          â†’ Import/export
â”‚   â”œâ”€â”€ parser.vala
â”‚   â””â”€â”€ export-operation.vala
â””â”€â”€ backends/                    â†’ Persistence
```

**Questions to answer:**
- What are the main UI components?
- Where does data come from?
- How is data persisted?
- What operations are supported (CRUD)?

### Step 1.2: Identify Over-Engineering

Look for patterns that exist because of framework constraints, not essential complexity:

| Pattern | Why It Exists | Do You Need It? |
|---------|---------------|-----------------|
| "Chunk" system | Folks requires valid data during edits | No â€” use simple fields |
| Operation classes | Async D-Bus operations need tracking | No â€” use synchronous file I/O |
| Persona aggregation | Multiple backends merged per contact | No â€” one backend at a time |
| Complex state machine | Handle D-Bus async states | No â€” simpler state enum |

**Rule:** If you can't explain why you need something, you don't need it.

### Step 1.3: Extract Core Concepts

From your analysis, identify the essential pieces:

**Data Model:**
- What fields does a record have?
- What's the minimum viable set?

**Operations:**
- Create, Read, Update, Delete
- Search/filter
- Import/export (if needed)

**UI Components:**
- List view (left pane)
- Detail view (right pane)
- Edit dialog
- Empty states

---

## Phase 2: Architecture Mapping

### Step 2.1: Map to Ruby Patterns

Translate the essential architecture to Ruby:

```
Original (Vala)              Ruby Equivalent
â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
Contact (GObject)         â†’ Contact < GLib::Object
Store                     â†’ ContactStore (wraps backend + ListStore)
ContactList               â†’ ListView with factory
ContactPane               â†’ ContactPane class
ContactEditor             â†’ ContactEditor class
Backend (EDS/Folks)       â†’ Backend (abstract)
                          â†’ JsonBackend
                          â†’ VCardBackend
```

### Step 2.2: Define the Data Flow

Draw the data flow through your app:

```
â”Œâ”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”
â”‚  Backend (JSON/VCard)                                       â”‚
â”‚    â†“ load()                                                 â”‚
â”‚  ContactStore                                               â”‚
â”‚    â†“ list_store (Gio::ListStore)                           â”‚
â”‚  FilterListModel                                            â”‚
â”‚    â†“ (optional: SortListModel)                             â”‚
â”‚  SingleSelection                                            â”‚
â”‚    â†“                                                        â”‚
â”‚  ListView â†â”€â”€factoryâ”€â”€â†’ List Items                          â”‚
â”‚    â†“ selection changed                                      â”‚
â”‚  ContactPane.show_contact(selected)                         â”‚
â””â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”˜
```

### Step 2.3: Define Component Boundaries

Each class has a single responsibility:

| Class | Responsibility |
|-------|----------------|
| Contact | Data model (GObject for ListStore) |
| Backend | Persistence (load/save/delete) |
| ContactStore | Manage list + selection + backend coordination |
| ContactPane | Display contact details |
| ContactEditor | Add/edit contact dialog |
| ContactsApp | Wire everything together |

---

## Phase 3: Minimal Viable Implementation

### Step 3.1: Start with Display Only

Build the simplest possible app that displays data:

```ruby
# Goal: Show a list of contacts, display details when selected
# No editing, no persistence, no search

class ContactsApp
  def build
    app.tap do
      app.signal_connect('activate') do
        # Window with paned layout
        # ListView on left
        # Detail labels on right
        # Hard-coded seed data
      end
    end
  end
end
```

**Checkpoint:** Can you see contacts and select them?

### Step 3.2: Add Persistence

Replace seed data with a backend:

```ruby
# Goal: Load contacts from JSON file
# Still no editing

def list_store
  @list_store ||= Gio::ListStore.new(Contact).tap do |store|
    backend.load.each do |hash|
      store.append(Contact.new(**hash))
    end
  end
end
```

**Checkpoint:** Does it load from file? Does it survive restart?

### Step 3.3: Add Create Operation

Add the ability to create new contacts:

```ruby
# Goal: Add button opens dialog, saves to backend

def show_add_dialog
  ContactEditor.new(
    contact: nil,
    on_save: ->(data) { add_contact(data) },
    on_cancel: -> { }
  ).tap do |editor|
    editor.build
    editor.present(window)
  end
end

def add_contact(data)
  @store.select_contact(@store.add_contact(**data))
end
```

**Checkpoint:** Can you add a contact? Does it persist?

### Step 3.4: Add Update Operation

Add editing:

```ruby
def show_edit_dialog
  @store.selected_contact.then do |contact|
    if contact
      ContactEditor.new(
        contact: contact,
        on_save: ->(data) { update_contact(data) },
        on_cancel: -> { }
      ).tap do |editor|
        editor.build
        editor.present(window)
      end
    end
  end
end
```

**Checkpoint:** Can you edit and see changes persist?

### Step 3.5: Add Delete Operation

Add deletion with undo:

```ruby
def delete_selected_contact
  @store.selected_contact.then do |contact|
    if contact
      @deleted_undo_info = @store.delete_contact(contact)
      show_undo_bar(contact.display_name)
    end
  end
end
```

**Checkpoint:** Full CRUD working?

---

## Phase 4: Incremental Feature Addition

### The Golden Rule

**Never remove working functionality when adding features.**

### Step 4.1: Add Search/Filter

```ruby
def contact_filter
  @contact_filter ||= Gtk::CustomFilter.new do |item|
    @query.empty? ||
      item.name.downcase.include?(@query) ||
      item.email.downcase.include?(@query)
  end
end
```

**Test:** Does CRUD still work after adding search?

### Step 4.2: Add More Fields

Add fields ONE AT A TIME:

1. Add field to Contact model
2. Add row to ContactPane
3. Add entry to ContactEditor
4. Update backend serialization
5. **Test that everything still works**
6. Repeat for next field

**Wrong approach:**
```ruby
# âŒ Don't do this â€” changing everything at once
class Contact
  attr_accessor :id, :name, :emails, :phones, :addresses, :birthday, :notes
  # Changed email â†’ emails (array), phone â†’ phones (array)
  # Broke all existing code that expected strings
end
```

**Right approach:**
```ruby
# âœ… Add one field at a time
class Contact
  attr_accessor :id, :name, :email, :phone
  attr_accessor :nickname  # â† Add this, test, then add next
end
```

---

## Phase 5: Refinement

### Step 5.1: Apply Style Rules

Review all code against the guide:

- [ ] Styles in memoized methods, not build
- [ ] Appends inside parent's tap block
- [ ] Single-line memoized methods when no styling
- [ ] No `return` statements â€” use `.then + if`
- [ ] No local variables â€” use `tap`
- [ ] Method chaining over multiple statements

### Step 5.2: Extract Classes When Needed

**When to extract:**
- Component has >10 widget methods
- Clear logical grouping exists
- Component could be reused

**Each extracted class follows the same pattern:**
- Constructor with callbacks
- `build` method returns root widget
- `update(data)` method for refreshing
- Memoized widget methods at bottom

### Step 5.3: Document Patterns

As you solve problems, document them:
- Ruby GTK4 quirks (GLib constants, key handling)
- Patterns that work
- Patterns that don't work

---

## Common Pitfalls

### Pitfall 1: Over-Engineering the Data Model

**Symptom:** You have value objects, arrays of typed fields, complex nested structures.

**Reality:** You probably just need strings.

```ruby
# âŒ Over-engineered
class Contact
  attr_accessor :emails  # Array of EmailAddress objects
  attr_accessor :phones  # Array of PhoneNumber objects
end

# âœ… Simple
class Contact
  attr_accessor :email   # String
  attr_accessor :phone   # String
end
```

### Pitfall 2: Conditional Visibility

**Symptom:** Fields appear/disappear based on whether they have data.

**Problem:** Adds complexity, causes layout shifts, breaks user expectations.

```ruby
# âŒ Wrong
email_row.visible = !contact.email.empty?

# âœ… Right â€” always show the row
email_value.label = contact.email
```

### Pitfall 3: Changing Data Format Mid-Project

**Symptom:** You renamed `email` to `emails` and now nothing works.

**Solution:** Keep backward compatibility or migrate all data.

### Pitfall 4: Testing Only the Happy Path

After every change, verify:
- [ ] Can you see the contact list?
- [ ] Can you select a contact?
- [ ] Can you see contact details?
- [ ] Can you add a new contact?
- [ ] Can you edit a contact?
- [ ] Can you delete a contact?
- [ ] Does search work?
- [ ] Does data persist after restart?

---

## Case Study: Contacts App

### What We Analyzed

GNOME Contacts (75 files, Vala):
- Complex "chunk" system for field management
- Folks/EDS integration for contact aggregation
- Operation classes for async D-Bus calls
- Multiple persona support

### What We Built

Ruby Contacts (8 files):
- Simple Contact with string fields
- Backend abstraction (JSON/VCard)
- ContactStore wrapping backend + ListStore
- ContactPane for display
- ContactEditor for add/edit
- Main app wiring

### Architecture Comparison

```
GNOME Contacts                    Ruby Contacts
â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
Folks.IndividualAggregator   â†’   ContactStore
Folks.Individual             â†’   Contact (GLib::Object)
Chunks (15+ classes)         â†’   String attributes
EDS backend                  â†’   Backend (abstract)
                                 â”œâ”€â”€ JsonBackend
                                 â””â”€â”€ VCardBackend
ContactSheet + ContactEditor â†’   ContactPane + ContactEditor
DeleteOperation class        â†’   delete_contact method
```

### Lines of Code

| Component | GNOME Contacts | Ruby Version |
|-----------|----------------|--------------|
| Contact model | ~500 lines | ~50 lines |
| Store | ~400 lines | ~100 lines |
| Contact display | ~600 lines | ~150 lines |
| Editor | ~800 lines | ~100 lines |
| **Total** | **~2300 lines** | **~400 lines** |

The Ruby version is ~6x smaller because we removed non-essential complexity.

---

## Summary Checklist

### Before Writing Code

- [ ] Analyzed directory structure
- [ ] Identified essential vs. over-engineered parts
- [ ] Mapped architecture to Ruby equivalents
- [ ] Defined data flow
- [ ] Defined component boundaries

### During Implementation

- [ ] Started with display-only
- [ ] Added persistence
- [ ] Added CRUD one operation at a time
- [ ] Tested after each addition
- [ ] Added features incrementally
- [ ] Never broke working functionality

### After Implementation

- [ ] Applied all style rules
- [ ] Extracted classes where appropriate
- [ ] Documented patterns and quirks
- [ ] Full test pass on all operations

---

## The Mantra

1. **Analyze** â€” Understand before building
2. **Simplify** â€” Remove non-essential complexity
3. **Implement** â€” Start minimal, add incrementally
4. **Test** â€” Verify after every change
5. **Refine** â€” Apply consistent patterns
