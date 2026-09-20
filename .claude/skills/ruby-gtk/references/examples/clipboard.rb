require 'gtk4'

class ClipboardDemo
  def build
    app.tap do
      app.signal_connect('activate') do
        app.add_window(window)

        window.tap do |win|
          win.title = 'Clipboard'
          win.resizable = true
          win.child = main_box
        end

        main_box.tap do |box|
          box.append(instructions_label)
          box.append(source_panel.build)
          box.append(separator)
          box.append(dest_panel.build)
        end

        window.present
      end
    end
  end

  def app = @app ||= Gtk::Application.new('org.example.clipboard', :default_flags)
  def window = @window ||= Gtk::Window.new
  def separator = @separator ||= Gtk::Separator.new(:horizontal)
  def clipboard = @clipboard ||= Gdk::Display.default.clipboard
  def source_panel = @source_panel ||= SourcePanel.new(clipboard)
  def dest_panel = @dest_panel ||= DestPanel.new(clipboard)

  def main_box
    @main_box ||= Gtk::Box.new(:vertical, 12).tap do |box|
      box.margin_start = 12
      box.margin_end = 12
      box.margin_top = 12
      box.margin_bottom = 12
    end
  end

  def instructions_label
    @instructions_label ||= Gtk::Label.new(
      '"Copy" will copy the selected data to the clipboard, "Paste" will show the current clipboard contents.'
    ).tap do |label|
      label.wrap = true
      label.max_width_chars = 40
    end
  end
end

class SourcePanel
  def initialize(clipboard)
    @clipboard = clipboard
  end

  def build
    @build ||= container.tap do |box|
      box.append(chooser)
      box.append(stack)
      box.append(copy_button)

      chooser.tap do |c|
        c.signal_connect('notify::selected') do
          stack.visible_child_name = %w[Text Color Image File Folder][c.selected]
          update_copy_sensitivity
        end
      end

      stack.tap do |s|
        s.add_named(text_source.build, 'Text')
        s.add_named(color_source.build, 'Color')
        s.add_named(image_source.build, 'Image')
        s.add_named(file_source.build, 'File')
        s.add_named(folder_source.build, 'Folder')
      end

      copy_button.tap do |btn|
        btn.signal_connect('clicked') { copy_to_clipboard }
      end

      text_source.on_changed { update_copy_sensitivity }
      update_copy_sensitivity
    end
  end

  def container = @container ||= Gtk::Box.new(:horizontal, 12)

  def chooser
    @chooser ||= Gtk::DropDown.new.tap do |c|
      c.valign = :center
      c.model = Gtk::StringList.new(['Text', 'Color', 'Image', 'File', 'Folder'])
    end
  end

  def stack
    @stack ||= Gtk::Stack.new.tap do |s|
      s.vexpand = true
    end
  end

  def copy_button
    @copy_button ||= Gtk::Button.new.tap do |btn|
      btn.label = '_Copy'
      btn.use_underline = true
      btn.valign = :center
    end
  end

  def text_source = @text_source ||= TextSource.new
  def color_source = @color_source ||= ColorSource.new
  def image_source = @image_source ||= ImageSource.new
  def file_source = @file_source ||= FileSource.new(-> { update_copy_sensitivity })
  def folder_source = @folder_source ||= FolderSource.new(-> { update_copy_sensitivity })

  def update_copy_sensitivity
    copy_button.sensitive = current_source.can_copy?
  end

  def current_source
    case stack.visible_child_name
    when 'Text' then text_source
    when 'Color' then color_source
    when 'Image' then image_source
    when 'File' then file_source
    when 'Folder' then folder_source
    end
  end

  def copy_to_clipboard
    current_source.copy_to(@clipboard)
  end
end

class DestPanel
  def initialize(clipboard)
    @clipboard = clipboard
  end

  def build
    @build ||= container.tap do |box|
      box.append(paste_button)
      box.append(type_label)
      box.append(stack)
      box.add_controller(drop_target)

      drop_target.tap do |drop|
        drop.signal_connect('drop') { |_, value, x, y| present_value(value); true }
      end

      paste_button.tap do |btn|
        btn.signal_connect('clicked') { paste_from_clipboard }
        @clipboard.signal_connect('changed') { update_sensitivity }
      end

      stack.tap do |s|
        s.add_named(empty_dest, '')
        s.add_named(text_dest, 'Text')
        s.add_named(image_dest, 'Image')
        s.add_named(color_dest, 'Color')
        s.add_named(file_dest, 'File')
      end

      update_sensitivity
    end
  end

  def container = @container ||= Gtk::Box.new(:horizontal, 12)
  def drop_target = @drop_target ||= Gtk::DropTarget.new(Gdk::Paintable.gtype, :copy)
  def empty_dest = @empty_dest ||= Gtk::Label.new

  def paste_button
    @paste_button ||= Gtk::Button.new.tap do |btn|
      btn.label = '_Paste'
      btn.use_underline = true
    end
  end

  def type_label
    @type_label ||= Gtk::Label.new.tap do |label|
      label.xalign = 0
      label.hexpand = true
    end
  end

  def stack
    @stack ||= Gtk::Stack.new.tap do |s|
      s.halign = :end
      s.valign = :center
    end
  end

  def text_dest
    @text_dest ||= Gtk::Label.new.tap do |label|
      label.halign = :end
      label.ellipsize = :end
    end
  end

  def image_dest
    @image_dest ||= Gtk::Image.new.tap do |img|
      img.halign = :end
      img.pixel_size = 48
    end
  end

  def color_dest
    @color_dest ||= Gtk::ColorDialogButton.new(Gtk::ColorDialog.new).tap do |btn|
      btn.halign = :end
      btn.can_target = false
    end
  end

  def file_dest
    @file_dest ||= Gtk::Label.new.tap do |label|
      label.halign = :end
      label.ellipsize = :start
    end
  end

  def update_sensitivity
    @clipboard.formats.to_s.then do |format_string|
      paste_button.sensitive =
        format_string.include?('gchararray') ||
        format_string.include?('Texture') ||
        format_string.include?('Paintable') ||
        format_string.include?('RGBA') ||
        format_string.include?('File')
    end
  end

  def paste_from_clipboard
    @clipboard.formats.to_s.then do |format_string|
      if format_string.include?('Texture')
        Gdk::Texture.gtype
      elsif format_string.include?('Paintable')
        Gdk::Paintable.gtype
      elsif format_string.include?('RGBA')
        Gdk::RGBA.gtype
      elsif format_string.include?('File')
        Gio::File.gtype
      elsif format_string.include?('gchararray')
        GLib::Type['gchararray']
      end
    end.then do |gtype|
      if gtype
        @clipboard.read_value_async(gtype, 0, nil) do |_, result|
          present_value(@clipboard.read_value_finish(result).value)
        end
      end
    end
  end

  def present_value(value)
    case value
    when Gdk::Paintable
      stack.visible_child_name = 'Image'
      image_dest.paintable = value
      type_label.label = 'Image'
    when Gdk::RGBA
      stack.visible_child_name = 'Color'
      color_dest.rgba = value
      type_label.label = 'Color'
    when Gio::File
      stack.visible_child_name = 'File'
      file_dest.label = value.path
      type_label.label = 'File'
    when String
      stack.visible_child_name = 'Text'
      text_dest.label = value
      type_label.label = 'Text'
    end
  end
end

class FolderSource
  def initialize(on_changed = nil)
    @folder = nil
    @on_changed = on_changed
  end

  def build
    @build ||= button.tap do |btn|
      btn.child = button_label
      btn.add_controller(drag_source)

      drag_source.tap do |drag|
        drag.signal_connect('prepare') { Gdk::ContentProvider.new_for_value(@folder) if @folder }
      end

      btn.signal_connect('clicked') { open_dialog }
    end
  end

  def button
    @button ||= Gtk::Button.new.tap do |btn|
      btn.valign = :center
    end
  end

  def button_label
    @button_label ||= Gtk::Label.new('—').tap do |l|
      l.xalign = 0
      l.ellipsize = :start
    end
  end

  def drag_source
    @drag_source ||= Gtk::DragSource.new.tap do |drag|
      drag.propagation_phase = :capture
    end
  end

  def can_copy? = !!@folder

  def copy_to(clipboard)
    clipboard.set(@folder) if @folder
  end

  def open_dialog
    Gtk::FileDialog.new.tap do |dialog|
      dialog.select_folder(build.get_ancestor(Gtk::Window), nil) do |_, result|
        @folder = dialog.select_folder_finish(result)
        button_label.label = @folder.path
        @on_changed&.call
      rescue StandardError
        # User cancelled
      end
    end
  end
end

class TextSource
  def build
    @build ||= entry
  end

  def entry
    @entry ||= Gtk::Entry.new.tap do |e|
      e.valign = :center
      e.text = 'Copy this!'
    end
  end

  def on_changed(&block)
    entry.signal_connect('notify::text', &block)
  end

  def can_copy? = !entry.text.empty?

  def copy_to(clipboard)
    clipboard.set(entry.text)
  end
end

class ColorSource
  def build
    @build ||= color_button
  end

  def color_button
    @color_button ||= Gtk::ColorDialogButton.new(Gtk::ColorDialog.new).tap do |btn|
      btn.valign = :center
    end
  end

  def can_copy? = true

  def copy_to(clipboard)
    clipboard.set(color_button.rgba)
  end
end

class ImageSource
  ICONS = ['org.gtk.Demo4', 'face-smile-symbolic', 'face-laugh-symbolic'].freeze

  def build
    @build ||= container.tap do |box|
      ICONS.each_with_index do |icon_name, i|
        Gtk::ToggleButton.new.tap do |btn|
          btn.active = i.zero?
          btn.group = @first_button unless i.zero?
          @first_button ||= btn
          btn.child = Gtk::Image.new(icon_name:, pixel_size: 48)

          Gtk::DragSource.new.tap do |drag|
            drag.signal_connect('prepare') { Gdk::ContentProvider.new_for_value(btn.child.paintable) }
            btn.add_controller(drag)
          end

          box.append(btn)
        end
      end
    end
  end

  def container
    @container ||= Gtk::Box.new(:horizontal, 0).tap do |box|
      box.valign = :center
      box.add_css_class('linked')
    end
  end

  def can_copy? = true

  def copy_to(clipboard)
    active_image.then do |image|
      if image
        paintable_for(image).then do |paintable|
          clipboard.set(paintable) if paintable
        end
      end
    end
  end

  def active_image
    build.first_child.then do |btn|
      btn = btn.next_sibling until btn.nil? || btn.active?
      btn&.child
    end
  end

  def paintable_for(image)
    case image.storage_type.nick
    when 'icon-name'
      Gtk::IconTheme.get_for_display(image.display).lookup_icon(image.icon_name, 48)
    when 'paintable'
      image.paintable
    end
  end
end

class FileSource
  def initialize(on_changed = nil)
    @file = nil
    @on_changed = on_changed
  end

  def build
    @build ||= button.tap do |btn|
      btn.child = button_label
      btn.add_controller(drag_source)

      drag_source.tap do |drag|
        drag.signal_connect('prepare') { Gdk::ContentProvider.new_for_value(@file) if @file }
      end

      btn.signal_connect('clicked') { open_dialog }
    end
  end

  def button
    @button ||= Gtk::Button.new.tap do |btn|
      btn.valign = :center
    end
  end

  def button_label
    @button_label ||= Gtk::Label.new('—').tap do |l|
      l.xalign = 0
      l.ellipsize = :start
    end
  end

  def drag_source
    @drag_source ||= Gtk::DragSource.new.tap do |drag|
      drag.propagation_phase = :capture
    end
  end

  def can_copy? = !!@file

  def copy_to(clipboard)
    clipboard.set(@file) if @file
  end

  def open_dialog
    Gtk::FileDialog.new.tap do |dialog|
      dialog.open(build.get_ancestor(Gtk::Window), nil) do |_, result|
        @file = dialog.open_finish(result)
        button_label.label = @file.path
        @on_changed&.call
      rescue StandardError
        # User cancelled
      end
    end
  end
end

ClipboardDemo.new.build.run
