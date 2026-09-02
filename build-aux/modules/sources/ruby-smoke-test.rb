#!/usr/bin/env ruby
# Smoke test for the bundled Ruby toolchain.
#
# Verifies that CRuby, ruby-gnome and the GNOME typelibs bundled in the
# Flatpak can build and show a GTK4 + Libadwaita window, and that the
# Workbench typelib (used by the Ruby previewer for Workbench::PreviewWindow)
# is loadable.
#
#   flatpak run --command=workbench-ruby-smoke-test re.sonny.Workbench.Devel

require "gtk4"
require "adwaita"

puts "ruby           #{RUBY_VERSION} (#{RUBY_PLATFORM})"
puts "gobject-intro  #{Gem.loaded_specs["gobject-introspection"].version}"
puts "gtk4 gem       #{Gem.loaded_specs["gtk4"].version}"
puts "adwaita gem    #{Gem.loaded_specs["adwaita"].version}"

begin
  GObjectIntrospection::Repository.default.require("Workbench", "0")
  puts "Workbench typelib loadable"
rescue StandardError => error
  # Only available once libworkbench is installed alongside.
  warn "Workbench typelib unavailable: #{error.message}"
end

Adw.init

application = Adw::Application.new("re.sonny.Workbench.RubySmokeTest", :default_flags)

application.signal_connect("activate") do |app|
  window = Adw::ApplicationWindow.new(app)
  window.set_default_size(360, 200)

  toolbar = Adw::ToolbarView.new
  toolbar.add_top_bar(Adw::HeaderBar.new)

  status = Adw::StatusPage.new
  status.title = "Ruby works"
  gtk_version = defined?(Gtk::Version::STRING) ? Gtk::Version::STRING : "?"
  status.description = "GTK #{gtk_version} • Ruby #{RUBY_VERSION}"
  toolbar.content = status

  window.content = toolbar
  window.present

  puts "window presented"
end

exit(application.run([]))
