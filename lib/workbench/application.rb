# frozen_string_literal: true

require "gtk4"
require "adwaita"

module Workbench
  # The port's application: one window, and a status page saying the port has
  # not been written yet. Everything else grows from here — replace the status
  # page with the real content, keep the shape.
  #
  # House style (see .claude/skills/ruby-gtk): every widget is a memoized
  # method, all configuration lives in its `tap`, assembly happens only in
  # `build`, and the launcher is one expression.
  class Application
    def build
      app.tap do
        app.signal_connect("activate") do
          window.tap do |win|
            win.content = toolbar_view
          end

          toolbar_view.tap do |view|
            view.add_top_bar(header_bar)
            view.content = status_page
          end

          window.present
        end
      end
    end

    # Adwaita::Application is broken in the Ruby bindings; the application
    # object comes from Gtk and only the window is Adwaita.
    def app = @app ||= Gtk::Application.new("org.rubygtkproject.Workbench", :default_flags)

    def window
      @window ||= Adwaita::ApplicationWindow.new(app).tap do |win|
        win.title = "workbench"
        win.set_default_size(800, 600)
      end
    end

    def toolbar_view = @toolbar_view ||= Adwaita::ToolbarView.new
    def header_bar = @header_bar ||= Adwaita::HeaderBar.new

    def status_page
      @status_page ||= Adwaita::StatusPage.new.tap do |page|
        page.title = "workbench"
        page.description = "The Ruby port has not been written yet."
        page.icon_name = "applications-engineering-symbolic"
      end
    end
  end
end
