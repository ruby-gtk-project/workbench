require 'gtk4'

class FileBrowserDemo
  def build
    app.tap do
      app.signal_connect('activate') do
        app.add_window(window)

        window.tap do |win|
          win.title = 'File browser'
          win.set_default_size(600, 400)
          win.titlebar = header_bar
          win.child = scrolled_window
        end

        header_bar.tap do |hb|
          hb.pack_start(up_button)
          hb.pack_end(view_switcher_box)

          up_button.tap do |btn|
            btn.signal_connect('clicked') { navigate_up }
          end

          view_switcher_box.tap do |box|
            views.each_with_index do |view, i|
              Gtk::ToggleButton.new.tap do |btn|
                btn.icon_name = view[:icon_name]
                btn.tooltip_text = view[:title]
                btn.active = i.zero?
                btn.group = @first_view_button unless i.zero?
                @first_view_button ||= btn

                btn.signal_connect('toggled') do
                  update_main_view(view) if btn.active?
                end

                box.append(btn)
              end
            end
          end
        end

        scrolled_window.tap do |sw|
          sw.child = grid_view

          grid_view.tap do |gv|
            gv.model = file_selection
            gv.signal_connect('activate') { |_, pos| on_file_activated(pos) }
          end
        end

        dir_list.file = Gio::File.new_for_path(Dir.pwd)
        update_main_view(views.first)

        grid_view.grab_focus
        window.present
      end
    end
  end

  def app = @app ||= Gtk::Application.new('org.example.filebrowser', :default_flags)
  def window = @window ||= Gtk::Window.new
  def header_bar = @header_bar ||= Gtk::HeaderBar.new
  def scrolled_window = @scrolled_window ||= Gtk::ScrolledWindow.new

  def up_button
    @up_button ||= Gtk::Button.new.tap do |btn|
      btn.icon_name = 'go-up-symbolic'
    end
  end

  def view_switcher_box
    @view_switcher_box ||= Gtk::Box.new(:horizontal, 0).tap do |box|
      box.add_css_class('linked')
    end
  end

  def grid_view
    @grid_view ||= Gtk::GridView.new.tap do |gv|
      gv.max_columns = 15
    end
  end

  def dir_list
    @dir_list ||= Gtk::DirectoryList.new(
      'standard::name,standard::display-name,standard::icon,standard::size,standard::content-type,standard::file,standard::type',
      nil
    )
  end

  def file_selection
    @file_selection ||= Gtk::SingleSelection.new(dir_list)
  end

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
      },
      {
        icon_name: 'view-paged-symbolic',
        title: 'Paged',
        orientation: :horizontal,
        factory: paged_factory
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
        item.item.then do |info|
          item.child.first_child.tap do |image|
            image.gicon = info.icon if info
            image.next_sibling.label = info&.display_name || ''
          end
        end
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
            l.wrap_mode = :word_char
            l.lines = 2
            l.ellipsize = :end
            l.width_chars = 10
            l.max_width_chars = 30
          end)
        end
      end

      f.signal_connect('bind') do |_, item|
        item.item.then do |info|
          item.child.first_child.tap do |image|
            image.gicon = info.icon if info
            image.next_sibling.label = info&.display_name || ''
          end
        end
      end
    end
  end

  def paged_factory
    @paged_factory ||= Gtk::SignalListItemFactory.new.tap do |f|
      f.signal_connect('setup') do |_, item|
        item.child = Gtk::Box.new(:horizontal, 6).tap do |box|
          box.append(Gtk::Image.new.tap { |i| i.icon_size = :large })
          box.append(Gtk::Box.new(:vertical, 2).tap do |vbox|
            vbox.append(Gtk::Label.new.tap { |l| l.halign = :start })
            vbox.append(Gtk::Label.new.tap { |l| l.halign = :start; l.add_css_class('dim-label') })
            vbox.append(Gtk::Label.new.tap { |l| l.halign = :start; l.add_css_class('dim-label') })
          end)
        end
      end

      f.signal_connect('bind') do |_, item|
        item.item.then do |info|
          item.child.first_child.tap do |image|
            image.gicon = info.icon if info

            image.next_sibling.first_child.tap do |name_label|
              name_label.label = info&.display_name || ''
              name_label.next_sibling.tap do |size_label|
                size_label.label = info ? GLib.format_size(info.size) : ''
                size_label.next_sibling.label = info&.content_type || ''
              end
            end
          end
        end
      end
    end
  end

  def update_main_view(view)
    grid_view.factory = view[:factory]
    grid_view.orientation = view[:orientation]
  end

  def navigate_up
    dir_list.file&.parent.then do |parent|
      dir_list.file = parent if parent
    end
  end

  def on_file_activated(pos)
    file_selection.get_item(pos).then do |info|
      if info && info.file_type == :directory
        info.attribute_object('standard::file').then do |file|
          dir_list.file = file if file
        end
      end
    end
  end
end

FileBrowserDemo.new.build.run
