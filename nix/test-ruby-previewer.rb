#!/usr/bin/env ruby
# frozen_string_literal: true

# Drives src/langs/ruby/ruby-previewer.rb the way Workbench does, without
# needing a Workbench build.
#
# Stands in for src/Previewer/DBusPreviewer.js: opens a private D-Bus server on
# a unix socket, spawns the previewer against it, then calls the same methods
# External.js calls — UpdateUi, UpdateCss, Run, OpenWindow, Screenshot — and
# checks the WindowOpen signal and the ColorScheme property.
#
#   nix develop --command ./nix/test-ruby-previewer.rb
#
# Pass --keep-open to leave the preview window up instead of exiting.

require "gio2"
require "tmpdir"

ROOT = File.expand_path("..", __dir__)
XML_PATH = File.join(ROOT, "src/Previewer/previewer.xml")
PREVIEWER = File.join(ROOT, "src/langs/ruby/ruby-previewer.rb")
INTERFACE_NAME = "re.sonny.Workbench.previewer_module"
OBJECT_PATH = "/re/sonny/workbench/previewer_module"

keep_open = ARGV.include?("--keep-open")

failures = []
def check(label, failures)
  yield
  puts "  ok   #{label}"
rescue StandardError => error
  puts "  FAIL #{label}: #{error.class}: #{error.message}"
  failures << label
end

Dir.mktmpdir("workbench-ruby-previewer") do |tmp|
  # A demo, as Workbench would have written it to the session directory.
  File.write(File.join(tmp, "main.rb"), <<~DEMO)
    box = Workbench.builder.get_object("subtitle")

    button = Gtk::Button.new(label: "Press me")
    button.margin_top = 6
    button.css_classes = ["suggested-action"]
    box.append(button)

    puts "demo ran, window is a \#{Workbench.window.class}"
  DEMO

  ui = <<~UI
    <?xml version="1.0" encoding="UTF-8"?>
    <interface>
      <object class="GtkBox" id="subtitle">
        <property name="orientation">vertical</property>
        <child>
          <object class="GtkLabel">
            <property name="label">Ruby previewer</property>
          </object>
        </child>
      </object>
    </interface>
  UI

  socket = File.join(tmp, "socket")
  guid = Gio::DBus.generate_guid
  # ruby-gnome maps g_dbus_server_new_sync onto .new; there is no .new_sync.
  server = Gio::DBusServer.new(
    "unix:path=#{socket}",
    Gio::DBusServerFlags::AUTHENTICATION_REQUIRE_SAME_USER,
    guid,
    nil,
  )
  server.start

  connection = nil
  server.signal_connect("new-connection") do |_server, new_connection|
    connection = new_connection
    true
  end

  pid = spawn(RbConfig.ruby, PREVIEWER, XML_PATH, server.client_address)
  at_exit { Process.kill("TERM", pid) rescue nil }

  context = GLib::MainContext.default
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10
  until connection || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
    context.iteration(false)
    sleep 0.01
  end
  abort "previewer never connected" if connection.nil?
  puts "connected"

  # The connection being up does not mean the object is exported yet.
  # DBusPreviewer.js has the same race and papers over it with a 100ms timeout.
  20.times do
    break if (
      connection.call_sync(nil, OBJECT_PATH, "org.freedesktop.DBus.Introspectable",
                           "Introspect", nil, nil, :none, 200) rescue nil
    )
    50.times { context.iteration(false) }
    sleep 0.05
  end

  window_open_events = []
  connection.signal_subscribe(nil, INTERFACE_NAME, "WindowOpen", OBJECT_PATH, nil, :none) do |*args|
    window_open_events << Array(args.last).first
  end

  def call(connection, name, parameters = nil)
    connection.call_sync(nil, OBJECT_PATH, INTERFACE_NAME, name, parameters, nil, :none, 5000)
  end

  puts "\ncalling:"

  check("UpdateUi", failures) do
    call(connection, "UpdateUi", GLib::Variant.parse("(#{GLib::Variant.new(ui)}, 'subtitle', '')", "(sss)"))
  end

  check("UpdateCss", failures) do
    call(connection, "UpdateCss", GLib::Variant.parse("(#{GLib::Variant.new("button { font-weight: bold; }")},)", "(s)"))
  end

  check("Run", failures) do
    call(connection, "Run",
         GLib::Variant.parse("(#{GLib::Variant.new(tmp)}, #{GLib::Variant.new("file://#{tmp}")})", "(ss)"))
  end

  check("ColorScheme get", failures) do
    value = connection.call_sync(nil, OBJECT_PATH, "org.freedesktop.DBus.Properties", "Get",
                                 GLib::Variant.parse("('#{INTERFACE_NAME}', 'ColorScheme')", "(ss)"),
                                 nil, :none, 5000)
    raise "unexpected #{value.inspect}" unless Array(value).first.is_a?(Integer)
  end

  check("ColorScheme set", failures) do
    connection.call_sync(nil, OBJECT_PATH, "org.freedesktop.DBus.Properties", "Set",
                         GLib::Variant.parse("('#{INTERFACE_NAME}', 'ColorScheme', <1>)", "(ssv)"),
                         nil, :none, 5000)
  end

  check("OpenWindow", failures) do
    call(connection, "OpenWindow", GLib::Variant.parse("(400, 300)", "(ii)"))
  end

  200.times { context.iteration(false); sleep 0.005 }

  check("WindowOpen signal", failures) do
    raise "no WindowOpen received" if window_open_events.empty?
    raise "got #{window_open_events.inspect}" unless window_open_events.include?(true)
  end

  screenshot = File.join(tmp, "shot.png")
  check("Screenshot", failures) do
    result = call(connection, "Screenshot",
                  GLib::Variant.parse("(#{GLib::Variant.new(screenshot)},)", "(s)"))
    raise "returned #{result.inspect}" unless Array(result).first == true
    raise "no file written" unless File.size?(screenshot)
  end

  check("EnableInspector", failures) do
    call(connection, "EnableInspector", GLib::Variant.parse("(false,)", "(b)"))
  end

  if keep_open
    puts "\n--keep-open: window left up, ctrl-c to quit"
    loop { context.iteration(true) }
  end

  check("CloseWindow", failures) do
    call(connection, "CloseWindow")
  end

  100.times { context.iteration(false); sleep 0.005 }
end

puts
if failures.empty?
  puts "all previewer calls passed"
else
  puts "#{failures.size} failed: #{failures.join(", ")}"
  exit 1
end
