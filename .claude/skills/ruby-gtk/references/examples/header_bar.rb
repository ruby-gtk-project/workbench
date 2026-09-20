require 'gtk4'

class HeaderBarDemo
  def build
    app.tap do
      app.signal_connect('activate') do
        app.add_window(window)

        window.tap do |win|
          win.title = 'Welcome to the Hotel California'
          win.set_default_size(600, 400)
          win.titlebar = header_bar
          win.child = content
        end

        header_bar.tap do |header|
          header.pack_start(nav_box)
          header.pack_start(toggle_switch)
          header.pack_end(checkout_button)

          nav_box.tap do |box|
            box.append(back_button)
            box.append(forward_button)
          end
        end

        window.present
      end
    end
  end

  def app = @app ||= Gtk::Application.new('org.example.headerbar', :default_flags)
  def window = @window ||= Gtk::Window.new
  def header_bar = @header_bar ||= Gtk::HeaderBar.new
  def toggle_switch = @toggle_switch ||= Gtk::Switch.new
  def content = @content ||= Gtk::TextView.new

  def nav_box
    @nav_box ||= Gtk::Box.new(:horizontal, 0).tap do |box|
      box.add_css_class('linked')
    end
  end

  def back_button
    @back_button ||= Gtk::Button.new.tap do |btn|
      btn.icon_name = 'go-previous-symbolic'
      btn.tooltip_text = 'Back'
    end
  end

  def forward_button
    @forward_button ||= Gtk::Button.new.tap do |btn|
      btn.icon_name = 'go-next-symbolic'
      btn.tooltip_text = 'Forward'
    end
  end

  def checkout_button
    @checkout_button ||= Gtk::Button.new.tap do |btn|
      btn.icon_name = 'mail-send-receive-symbolic'
      btn.tooltip_text = 'Check out'
    end
  end
end

HeaderBarDemo.new.build.run
