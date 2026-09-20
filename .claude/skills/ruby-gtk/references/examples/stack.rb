require 'gtk4'

class StackDemo
  def build
    app.tap do
      app.signal_connect('activate') do
        window.tap do |win|
          win.title = 'Stack'
          win.resizable = false
          win.child = main_box
        end

        main_box.tap do |box|
          box.append(stack_switcher)
          box.append(stack)

          stack.tap do |s|
            s.add_titled(page1, 'page1', 'Page 1')
            s.add_titled(page2, 'page2', 'Page 2')

            s.add_named(page3, 'page3').tap do |page|
              page.icon_name = 'face-laugh-symbolic'
            end
          end
        end

        window.present
      end
    end
  end

  def app = @app ||= Gtk::Application.new('org.example.stack', :default_flags)
  def window = @window ||= Gtk::ApplicationWindow.new(app)
  def main_box = @main_box ||= Gtk::Box.new(:vertical, 0)

  def stack_switcher
    @stack_switcher ||= Gtk::StackSwitcher.new.tap do |switcher|
      switcher.stack = stack
      switcher.halign = :center
    end
  end

  def stack
    @stack ||= Gtk::Stack.new.tap do |stack|
      stack.transition_type = :crossfade
    end
  end

  def page1
    @page1 ||= Gtk::Image.new.tap do |img|
      img.margin_top = 20
      img.margin_bottom = 20
      img.pixel_size = 100
      img.icon_name = 'org.gtk.Demo4'
    end
  end

  def page2
    @page2 ||= Gtk::CheckButton.new.tap do |btn|
      btn.label = 'Page 2'
      btn.halign = :center
      btn.valign = :center
    end
  end

  def page3
    @page3 ||= Gtk::Spinner.new.tap do |spin|
      spin.halign = :center
      spin.valign = :center
      spin.start
    end
  end
end

StackDemo.new.build.run
