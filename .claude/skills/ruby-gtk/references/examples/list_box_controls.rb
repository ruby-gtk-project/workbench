require 'gtk4'

class ListBoxControlsDemo
  def build
    app.tap do
      app.signal_connect('activate') do
        app.add_window(window)

        window.tap do |win|
          win.title = 'List Box — Controls'
          win.default_height = 400
          win.child = scrolled_window
        end

        scrolled_window.tap do |sw|
          sw.child = viewport

          viewport.tap do |vp|
            vp.child = main_box

            main_box.tap do |box|
              box.append(group1_label)
              box.append(group1_list.build)
              box.append(group2_label)
              box.append(group2_list.build)
            end
          end
        end

        size_group.tap do |sg|
          sg.add_widget(group1_list.switch_label)
          sg.add_widget(group1_list.check_label)
          sg.add_widget(group1_list.image_label)
          sg.add_widget(group2_list.scale_label)
          sg.add_widget(group2_list.spin_label)
          sg.add_widget(group2_list.dropdown_label)
          sg.add_widget(group2_list.entry_label)
        end

        window.present
      end
    end
  end

  def app = @app ||= Gtk::Application.new('org.example.listbox_controls', :default_flags)
  def window = @window ||= Gtk::Window.new
  def group1_list = @group1_list ||= Group1List.new
  def group2_list = @group2_list ||= Group2List.new
  def size_group = @size_group ||= Gtk::SizeGroup.new(:horizontal)

  def scrolled_window
    @scrolled_window ||= Gtk::ScrolledWindow.new.tap do |sw|
      sw.hscrollbar_policy = :never
      sw.min_content_height = 200
      sw.hexpand = false
      sw.vexpand = true
    end
  end

  def viewport
    @viewport ||= Gtk::Viewport.new.tap do |vp|
      vp.scroll_to_focus = true
    end
  end

  def main_box
    @main_box ||= Gtk::Box.new(:vertical, 0).tap do |box|
      box.margin_start = 60
      box.margin_end = 60
      box.margin_top = 30
      box.margin_bottom = 30
    end
  end

  def group1_label
    @group1_label ||= Gtk::Label.new('Group 1').tap do |label|
      label.xalign = 0
      label.margin_bottom = 10
      label.add_css_class('title-2')
    end
  end

  def group2_label
    @group2_label ||= Gtk::Label.new('Group 2').tap do |label|
      label.xalign = 0
      label.margin_top = 30
      label.margin_bottom = 10
      label.add_css_class('title-2')
    end
  end
end

class Group1List
  def build
    @build ||= list_box.tap do |list|
      list.signal_connect('row-activated') { |_, row| on_row_activated(row) }

      list.append(switch_row)
      list.append(check_row)
      list.append(image_row)

      switch_row.tap do |row|
        row.child = switch_box

        switch_box.tap do |box|
          box.append(switch_label)
          box.append(switch_widget)
        end
      end

      check_row.tap do |row|
        row.child = check_box

        check_box.tap do |box|
          box.append(check_label)
          box.append(check_widget)
        end
      end

      image_row.tap do |row|
        row.child = image_box

        image_box.tap do |box|
          box.append(image_label)
          box.append(image_widget)
        end
      end
    end
  end

  def switch_box = @switch_box ||= Gtk::Box.new(:horizontal, 0)
  def check_box = @check_box ||= Gtk::Box.new(:horizontal, 0)
  def image_box = @image_box ||= Gtk::Box.new(:horizontal, 0)

  def list_box
    @list_box ||= Gtk::ListBox.new.tap do |list|
      list.selection_mode = :none
      list.add_css_class('rich-list')
      list.add_css_class('boxed-list')
    end
  end

  def switch_row
    @switch_row ||= Gtk::ListBoxRow.new.tap do |row|
      row.selectable = false
    end
  end

  def check_row
    @check_row ||= Gtk::ListBoxRow.new.tap do |row|
      row.selectable = false
    end
  end

  def image_row
    @image_row ||= Gtk::ListBoxRow.new.tap do |row|
      row.selectable = false
    end
  end

  def switch_label
    @switch_label ||= Gtk::Label.new('Switch').tap do |label|
      label.xalign = 0
      label.halign = :start
      label.valign = :center
      label.hexpand = true
      label.mnemonic_widget = switch_widget
    end
  end

  def check_label
    @check_label ||= Gtk::Label.new('Check').tap do |label|
      label.xalign = 0
      label.halign = :start
      label.valign = :center
      label.hexpand = true
      label.mnemonic_widget = check_widget
    end
  end

  def image_label
    @image_label ||= Gtk::Label.new('Click here!').tap do |label|
      label.xalign = 0
      label.halign = :start
      label.valign = :center
      label.hexpand = true
    end
  end

  def switch_widget
    @switch_widget ||= Gtk::Switch.new.tap do |sw|
      sw.halign = :end
      sw.valign = :center
    end
  end

  def check_widget
    @check_widget ||= Gtk::CheckButton.new.tap do |chk|
      chk.halign = :end
      chk.valign = :center
      chk.margin_start = 10
      chk.margin_end = 10
      chk.active = true
    end
  end

  def image_widget
    @image_widget ||= Gtk::Image.new.tap do |img|
      img.icon_name = 'object-select-symbolic'
      img.halign = :end
      img.valign = :center
      img.margin_start = 10
      img.margin_end = 10
      img.opacity = 0
    end
  end

  def on_row_activated(row)
    case row
    when switch_row
      switch_widget.active = !switch_widget.active?
    when check_row
      check_widget.active = !check_widget.active?
    when image_row
      image_widget.opacity = 1.0 - image_widget.opacity
    end
  end
end

class Group2List
  def build
    @build ||= list_box.tap do |list|
      list.append(scale_row)
      list.append(spin_row)
      list.append(dropdown_row)
      list.append(entry_row)

      scale_row.tap do |row|
        row.child = scale_box

        scale_box.tap do |box|
          box.append(scale_label)
          box.append(scale_widget)
        end
      end

      spin_row.tap do |row|
        row.child = spin_box

        spin_box.tap do |box|
          box.append(spin_label)
          box.append(spin_widget)
        end
      end

      dropdown_row.tap do |row|
        row.child = dropdown_box

        dropdown_box.tap do |box|
          box.append(dropdown_label)
          box.append(dropdown_widget)
        end
      end

      entry_row.tap do |row|
        row.child = entry_box

        entry_box.tap do |box|
          box.append(entry_label)
          box.append(entry_widget)
        end
      end
    end
  end

  def scale_box = @scale_box ||= Gtk::Box.new(:horizontal, 0)
  def spin_box = @spin_box ||= Gtk::Box.new(:horizontal, 0)
  def dropdown_box = @dropdown_box ||= Gtk::Box.new(:horizontal, 0)
  def entry_box = @entry_box ||= Gtk::Box.new(:horizontal, 0)

  def list_box
    @list_box ||= Gtk::ListBox.new.tap do |list|
      list.selection_mode = :none
      list.add_css_class('rich-list')
      list.add_css_class('boxed-list')
    end
  end

  def scale_row
    @scale_row ||= Gtk::ListBoxRow.new.tap do |row|
      row.selectable = false
      row.activatable = false
    end
  end

  def spin_row
    @spin_row ||= Gtk::ListBoxRow.new.tap do |row|
      row.selectable = false
      row.activatable = false
    end
  end

  def dropdown_row
    @dropdown_row ||= Gtk::ListBoxRow.new.tap do |row|
      row.selectable = false
      row.activatable = false
    end
  end

  def entry_row
    @entry_row ||= Gtk::ListBoxRow.new.tap do |row|
      row.selectable = false
      row.activatable = false
    end
  end

  def scale_label
    @scale_label ||= Gtk::Label.new('Scale').tap do |label|
      label.xalign = 0
      label.halign = :start
      label.valign = :center
      label.hexpand = true
      label.mnemonic_widget = scale_widget
    end
  end

  def spin_label
    @spin_label ||= Gtk::Label.new('Spinbutton').tap do |label|
      label.xalign = 0
      label.halign = :start
      label.valign = :center
      label.hexpand = true
      label.mnemonic_widget = spin_widget
    end
  end

  def dropdown_label
    @dropdown_label ||= Gtk::Label.new('Dropdown').tap do |label|
      label.xalign = 0
      label.halign = :start
      label.valign = :center
      label.hexpand = true
      label.mnemonic_widget = dropdown_widget
    end
  end

  def entry_label
    @entry_label ||= Gtk::Label.new('Entry').tap do |label|
      label.xalign = 0
      label.halign = :start
      label.valign = :center
      label.hexpand = true
      label.mnemonic_widget = entry_widget
    end
  end

  def scale_widget
    @scale_widget ||= Gtk::Scale.new(:horizontal, Gtk::Adjustment.new(50, 0, 100, 1, 10, 0)).tap do |scale|
      scale.halign = :end
      scale.valign = :center
      scale.draw_value = false
      scale.width_request = 150
    end
  end

  def spin_widget
    @spin_widget ||= Gtk::SpinButton.new(Gtk::Adjustment.new(50, 0, 100, 1, 10, 0), 1, 0).tap do |spin|
      spin.halign = :end
      spin.valign = :center
    end
  end

  def dropdown_widget
    @dropdown_widget ||= Gtk::DropDown.new.tap do |dd|
      dd.halign = :end
      dd.valign = :center
      dd.model = Gtk::StringList.new(['Choice 1', 'Choice 2', 'Choice 3', 'Choice 4'])
    end
  end

  def entry_widget
    @entry_widget ||= Gtk::Entry.new.tap do |entry|
      entry.halign = :end
      entry.valign = :center
      entry.placeholder_text = 'Type here…'
    end
  end
end

ListBoxControlsDemo.new.build.run
