#!/usr/bin/env ruby
# frozen_string_literal: true

# Minimal reproductions for every ruby-gnome defect documented in FINDINGS.md.
#
# Each case reports PRESENT (the bug still reproduces, the workaround is still
# needed) or FIXED (upstream has fixed it, the workaround can go). Run it after
# bumping the gems in build-aux/modules/ruby-gnome.json:
#
#   nix develop --command ./nix/ruby-gnome-findings.rb

require "gtk4"
require "adwaita"
require "tmpdir"

XML = <<~XML
  <node>
    <interface name="test.Iface">
      <method name="Method">
        <arg type="s" name="a" direction="in"/>
        <arg type="b" name="ok" direction="out"/>
      </method>
      <signal name="Sig"><arg type="s" name="m"/></signal>
      <property type="i" name="Prop" access="readwrite"/>
    </interface>
  </node>
XML

$present = 0
$fixed = 0

# `bug` is what the defect looks like. Returning true means it still
# reproduces.
def finding(id, title)
  still_broken = yield
  if still_broken
    $present += 1
    puts "  PRESENT  #{id}  #{title}"
  else
    $fixed += 1
    puts "  FIXED    #{id}  #{title} -- workaround can be removed"
  end
rescue StandardError => error
  $present += 1
  puts "  PRESENT  #{id}  #{title} (#{error.class}: #{error.message.to_s.lines.first.to_s.strip[0, 80]})"
end

puts "ruby #{RUBY_VERSION}, ruby-gnome #{Gem.loaded_specs["glib2"].version}"
puts

finding("RG-1", "DBusNodeInfo#interfaces returns junk instead of structs") do
  info = Gio::DBusNodeInfo.new(XML)
  # Should be [Gio::DBusInterfaceInfo]; is actually a String of one control
  # character. The count is right, only the elements are wrong.
  !info.interfaces.first.is_a?(Gio::DBusInterfaceInfo)
end

finding("RG-2", "DBusInterfaceInfo#methods / DBusMethodInfo#in_args likewise") do
  iface = Gio::DBusNodeInfo.new(XML).lookup_interface("test.Iface")
  method = iface.lookup_method("Method")
  !iface.methods.first.is_a?(Gio::DBusMethodInfo) ||
    !method.in_args.first.is_a?(Gio::DBusArgInfo)
end

finding("RG-3", "GLib::Variant.new cannot build tuple types") do
  begin
    GLib::Variant.new(["a", true], "(sb)")
    false
  rescue NotImplementedError
    true
  end
end

finding("RG-4", "DBusConnection.new_for_address is the async call and returns nil") do
  Dir.mktmpdir do |tmp|
    server = Gio::DBusServer.new(
      "unix:path=#{File.join(tmp, "s")}",
      Gio::DBusServerFlags::AUTHENTICATION_REQUIRE_SAME_USER,
      Gio::DBus.generate_guid,
      nil,
    )
    server.start
    server.signal_connect("new-connection") { |_s, _c| true }

    script = File.join(tmp, "client.rb")
    File.write(script, <<~CLIENT)
      require "gio2"
      flags = Gio::DBusConnectionFlags::AUTHENTICATION_CLIENT
      print Gio::DBusConnection.new_for_address(ARGV[0], flags).nil? ? "nil" : "connection"
    CLIENT

    read, write = IO.pipe
    pid = spawn(RbConfig.ruby, script, server.client_address, out: write)
    write.close
    context = GLib::MainContext.default
    100.times { context.iteration(false); sleep 0.02 }
    Process.wait(pid)
    read.read.strip == "nil"
  end
end

finding("RG-5", "method-call closure receives converted values, not a GLib::Variant") do
  # D-Bus path elements are [A-Za-z0-9_] only, so no tmpdir names here.
  path = "/findings/closure_args"
  connection = Gio.bus_get_sync(:session)
  iface = Gio::DBusNodeInfo.new(XML).lookup_interface("test.Iface")
  seen = nil
  connection.register_object(
    path, iface,
    lambda { |_c, _s, _p, _i, _m, parameters, invocation|
      seen = parameters.class
      invocation.return_value(GLib::Variant.parse("(true,)", "(b)"))
    },
    nil, nil
  )
  # The caller runs on another thread so this one can drive the main context.
  # Its reply may well arrive after the timeout, which does not matter: all we
  # need is for the closure to have been entered once.
  Thread.new do
    Thread.current.report_on_exception = false
    Gio.bus_get_sync(:session).call_sync(
      connection.unique_name, path, "test.Iface", "Method",
      GLib::Variant.parse("('x',)", "(s)"), nil, :none, 3000
    )
  rescue StandardError
    nil
  end
  context = GLib::MainContext.default
  200.times { break if seen; context.iteration(false); sleep 0.01 }
  raise "closure never ran" if seen.nil?

  seen != GLib::Variant
end

puts
puts "#{$present} present, #{$fixed} fixed"
puts "see FINDINGS.md" if $present.positive?
