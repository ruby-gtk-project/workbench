#!/usr/bin/env ruby
# frozen_string_literal: true

# The previewer for Ruby demos. It connects over D-Bus back to Workbench and
# loads demos, providing them with the `Workbench` API.
#
# This is the Ruby counterpart of src/langs/python/python-previewer.py and
# implements the same interface, src/Previewer/previewer.xml. Workbench spawns
# it through bin/workbench-ruby-previewer with two arguments:
#
#   argv[0]  path to previewer.xml
#   argv[1]  D-Bus address of the private server in DBusPreviewer.js

# The Ruby Adwaita bindings namespace everything under Adwaita::, not Adw::,
# and both gems initialise their library on require - there is no Gtk.init or
# Adwaita.init to call, unlike the gi.require_version + Gtk.init() preamble in
# python-previewer.py.
require "gtk4"
require "adwaita"
# Demos reach for GtkSource; the previewer loads it so they do not have to.
# ruby-gnome has no gem for WebKit or libshumate, so the Shumate/WebKit demos
# the Python previewer can run have no Ruby equivalent yet.
require "gtksourceview5"

require_relative "gdbus_ext"

INTERFACE_NAME = "re.sonny.Workbench.previewer_module"
OBJECT_PATH = "/re/sonny/workbench/previewer_module"

# dbus_method runs while the class body is being evaluated, so the interface
# has to be known before that — which means reading argv here rather than in
# the constructor. Falling back to the in-tree copy lets the previewer be run
# straight from a checkout.
PREVIEWER_XML = ARGV[0] || File.expand_path("../../Previewer/previewer.xml", __dir__)

# The Workbench typelib provides Workbench::PreviewWindow, the frameless window
# used when a demo's target is not itself a Gtk::Root. It ships inside the
# Flatpak, so outside one the previewer falls back to an Adwaita::Window.
module Workbench
  class Loader < GObjectIntrospection::Loader
  end

  begin
    resource = Gio::Resource.load(
      "/app/share/#{ENV.fetch("FLATPAK_ID")}/re.sonny.Workbench.libworkbench.gresource",
    )
    Gio::Resources.register(resource)
    Loader.load("Workbench", self)
    HAVE_PREVIEW_WINDOW = true
  rescue StandardError => error
    # Expected outside the Flatpak, where there is no libworkbench to load.
    warn "Workbench typelib unavailable, using Adwaita::Window (#{error.class})"
    HAVE_PREVIEW_WINDOW = false
  end
end

class Previewer
  extend GDBus::Template

  attr_reader :window, :builder, :target, :uri

  dbus_interface File.read(PREVIEWER_XML), INTERFACE_NAME

  def initialize
    @style_manager = Adwaita::StyleManager.default
    @css = nil
    @window = nil
    @builder = nil
    @target = nil
    @uri = nil
    @resource_icons = nil

    # See application.js
    icon_theme = Gtk::IconTheme.get_for_display(Gdk::Display.default)
    icon_theme.resource_path = [
      "/org/gtk/libgtk/icons/",
      "/org/gnome/Adwaita/icons/",
      "/re/sonny/Workbench/icons/",
    ]
    icon_theme.search_path = ["/usr/share/icons", "/app/share/icons"]
  end

  dbus_method def update_ui(content, target_id, original_id = "")
    @builder = Gtk::Builder.new(string: content)
    target = @builder.get_object(target_id)
    if target.nil?
      warn "Widget with target_id='#{target_id}' could not be found."
      return
    end

    @target = target
    @builder.expose_object(original_id, target) unless original_id.to_s.empty?

    # Not a Root/Window
    unless @target.is_a?(Gtk::Root)
      ensure_window
      set_child(@window, @target)
      return
    end

    # Set target as window directly
    if @window.nil? || @window.class != @target.class
      set_window(@target)
      return
    end

    # An Adwaita window owns its layout and takes `content`; a plain Gtk one
    # takes `child`. Asking the widget is steadier than listing the Adwaita
    # classes, and it covers Workbench::PreviewWindow too.
    if @target.respond_to?(:content=)
      child = @target.content
      @target.content = nil
    else
      child = @target.child
      @target.child = nil
    end
    set_child(@window, child)

    # Toplevel windows returned by these functions will stay around until the
    # user explicitly destroys them with gtk_window_destroy().
    # https://docs.gtk.org/gtk4/class.Builder.html
    @target.destroy if @target.is_a?(Gtk::Window)
  end

  dbus_method def update_css(content)
    display = Gdk::Display.default
    Gtk::StyleContext.remove_provider_for_display(display, @css) if @css

    @css = Gtk::CssProvider.new
    @css.signal_connect("parsing-error") do |_provider, section, error|
      start = section.start_location
      finish = section.end_location
      css_parser_error(
        error.message,
        start.lines, start.line_chars,
        finish.lines, finish.line_chars,
      )
    end
    @css.load_from_string(content)
    Gtk::StyleContext.add_provider_for_display(
      display, @css, Gtk::StyleProvider::PRIORITY_APPLICATION
    )
  end

  # `filename` is the session directory, not a file — same as the Python
  # previewer, whose Builder.js passes session.file.get_path().
  dbus_method def run(filename, uri)
    @uri = uri
    reload_icons(uri)

    # `load` re-executes on every call, unlike `require`, and wrapping it in an
    # anonymous module keeps each run's constants and top-level methods from
    # leaking into the next one. This is the piece the Python previewer cannot
    # do: it has to evict sys.modules and still cannot unload the old module.
    load(File.join(filename, "main.rb"), true)
  end

  dbus_method def close_window
    @window&.close
  end

  dbus_method def open_window(width, height)
    @window.set_default_size(width, height)
    @window.present
    window_open(true)
  end

  dbus_method def screenshot(path)
    paintable = Gtk::WidgetPaintable.new(@target)
    width = @target.width
    height = @target.height

    snapshot = Gtk::Snapshot.new
    paintable.snapshot(snapshot, width, height)
    node = snapshot.to_node
    if node.nil?
      warn "Could not get node snapshot, width: #{width}, height: #{height}"
      return false
    end

    renderer = @target.native.renderer
    rect = Graphene::Rect.new(0, 0, width.to_f, height.to_f)
    texture = renderer.render_texture(node, rect)
    texture.save_to_png(path)
    true
  end

  dbus_method def enable_inspector(enabled)
    Gtk::Window.interactive_debugging = enabled
  end

  dbus_signal :window_open
  dbus_signal :css_parser_error

  dbus_property :color_scheme

  def color_scheme
    @style_manager.color_scheme.to_i
  end

  def color_scheme=(value)
    @style_manager.color_scheme = Adwaita::ColorScheme.new(value)
  end

  # Resolves a path relative to the demo directory. Exposed to demos as
  # Workbench.resolve.
  def resolve(path)
    Gio::File.new_for_uri(@uri).resolve_relative_path(path).uri
  end

  private

  def reload_icons(uri)
    if @resource_icons
      Gio::Resources.unregister(@resource_icons)
      @resource_icons = nil
    end

    @resource_icons = Gio::Resource.load(
      Gio::File.new_for_uri(uri).get_child("icons.gresource").path,
    )
    Gio::Resources.register(@resource_icons)
  rescue StandardError
    # A demo without icons.gresource is the common case, not an error.
    @resource_icons = nil
  end

  def set_child(window, widget)
    window.respond_to?(:content=) ? window.content = widget : window.child = widget
  end

  def ensure_window
    return if @window

    set_window(
      Workbench::HAVE_PREVIEW_WINDOW ? Workbench::PreviewWindow.new : Adwaita::Window.new,
    )
  end

  def set_window(new_window)
    @window&.destroy
    @window = new_window
    @window.signal_connect("close-request") do
      window_open(false)
      @window = nil
      false
    end
  end
end

# The API demos see. Loading the typelib above already put PreviewWindow on
# this module; these three are what demo code actually uses, and they forward
# to the previewer rather than capturing its state, so a re-run picks up the
# new builder and window.
module Workbench
  class << self
    attr_accessor :previewer

    def builder
      previewer.builder
    end

    def window
      previewer.window
    end

    def resolve(path)
      previewer.resolve(path)
    end
  end
end

if $PROGRAM_NAME == __FILE__
  address = ARGV[1]
  abort "usage: #{$PROGRAM_NAME} <previewer.xml> <dbus-address>" if address.nil?

  previewer = Previewer.new
  Workbench.previewer = previewer

  # g_dbus_connection_new_for_address_sync is a constructor, so ruby-gnome
  # folds it into .new and dispatches on the arguments. .new_for_address is the
  # *async* function and returns nil, which is a quiet way to lose an hour.
  connection = Gio::DBusConnection.new(
    address,
    Gio::DBusConnectionFlags::AUTHENTICATION_CLIENT,
  )
  abort "could not connect to #{address}" if connection.nil?
  connection.exit_on_close = true

  GDBus.register_object(connection, OBJECT_PATH, previewer)

  GLib::MainLoop.new.run
end
