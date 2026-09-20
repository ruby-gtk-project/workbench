require 'gtk4'

class StackSidebarDemo
  PAGES = [
    'Welcome to GTK',
    'GtkStackSidebar Widget',
    'Automatic navigation',
    'Consistent appearance',
    'Scrolling',
    'Page 6',
    'Page 7',
    'Page 8',
    'Page 9'
  ].freeze

  def build
    app.tap do
      app.signal_connect('activate') do
        window.tap do |win|
          win.titlebar = header_bar
          win.title = 'Stack Sidebar'
          win.resizable = true
          win.child = main_box
        end

        main_box.tap do |box|
          box.append(sidebar)
          box.append(stack)

          stack.tap do |s|
            PAGES.each_with_index do |title, i|
              if i.zero? then welcome_image else Gtk::Label.new(title) end.then do |content|
                s.add_named(content, title).tap do |page|
                  page.title = title
                end
              end
            end
          end
        end

        window.present
      end
    end
  end

  def app = @app ||= Gtk::Application.new('org.example.stack_sidebar', :default_flags)
  def window = @window ||= Gtk::ApplicationWindow.new(app)
  def header_bar = @header_bar ||= Gtk::HeaderBar.new
  def main_box = @main_box ||= Gtk::Box.new(:horizontal, 0)

  def sidebar
    @sidebar ||= Gtk::StackSidebar.new.tap do |sb|
      sb.stack = stack
    end
  end

  def stack
    @stack ||= Gtk::Stack.new.tap do |s|
      s.transition_type = :slide_up_down
      s.hexpand = true
    end
  end

  def welcome_image
    @welcome_image ||= Gtk::Image.new.tap do |img|
      img.icon_name = 'org.gtk.Demo4'
      img.add_css_class('icon-dropshadow')
      img.pixel_size = 256
    end
  end
end

StackSidebarDemo.new.build.run
