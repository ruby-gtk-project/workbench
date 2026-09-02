# frozen_string_literal: true

# Turns a plain Ruby object into a D-Bus object, the way
# src/langs/python/gdbus_ext.py does for the Python previewer.
#
# ruby-gnome exposes g_dbus_connection_register_object_with_closures as
# Gio::DBusConnection#register_object, which is enough to build on, but two
# gaps make a helper necessary:
#
#   1. Struct-array fields on the introspection info objects come back as
#      garbage. Gio::DBusNodeInfo#interfaces, DBusInterfaceInfo#methods and
#      DBusMethodInfo#in_args each yield one-byte junk strings rather than
#      objects. Only the lookup_* methods return anything usable, and there is
#      no lookup for arguments, so argument signatures are scanned out of the
#      XML here instead of being read back from GLib.
#
#   2. GLib::Variant.new cannot build tuples. rbglib-variant.c raises
#      NotImplementedError for any type it does not special-case and no tuple
#      type is among them. Every D-Bus reply and signal payload is a tuple, so
#      they are assembled as GVariant text and handed to GLib::Variant.parse.
#      Element text comes from GLib::Variant#to_s, which escapes correctly, so
#      arbitrary strings survive the round trip.
#
# Usage:
#
#   class Previewer
#     extend GDBus::Template
#     dbus_interface File.read(xml_path), "re.sonny.Workbench.previewer_module"
#
#     dbus_method def update_ui(content, target_id, original_id = "")
#     end
#
#     dbus_signal :window_open
#     dbus_property :color_scheme
#   end
#
#   GDBus.register_object(connection, "/re/sonny/workbench/previewer_module",
#                         Previewer.new)

require "gio2"

module GDBus
  Error = Class.new(StandardError)

  # The subset of a D-Bus introspection document this helper needs: the
  # signature of every method, signal and property on one interface.
  #
  # This is a scanner, not an XML parser. rexml is a bundled gem and is not
  # guaranteed to be present (nixpkgs' ruby ships without it), and the only
  # document ever fed to it is src/Previewer/previewer.xml, which Workbench
  # generates itself. It is deliberately strict: anything it does not
  # recognise raises rather than being quietly skipped.
  class InterfaceSpec
    Method = Struct.new(:name, :in_signature, :out_signature)
    Signal = Struct.new(:name, :signature)
    Property = Struct.new(:name, :signature, :readable, :writable)

    attr_reader :name, :methods, :signals, :properties

    def self.parse(xml, interface_name)
      body = xml[
        %r{<interface\s+name="#{Regexp.escape(interface_name)}"\s*>(.*?)</interface>}m,
        1,
      ]
      raise Error, "no interface #{interface_name.inspect} in the XML" if body.nil?

      new(interface_name, body)
    end

    def initialize(name, body)
      @name = name
      @methods = scan_methods(body)
      @signals = scan_signals(body)
      @properties = scan_properties(body)
      freeze
    end

    private

    # <method name="X"> <arg .../> </method>, or <method name="X"/> when it
    # takes and returns nothing.
    def scan_methods(body)
      body.scan(%r{<method\s+([^>/]*?)\s*(?:/>|>(.*?)</method>)}m).to_h do |attributes, args|
        method_name = attribute(attributes, "name")
        directions = scan_args(args.to_s).group_by { |arg| arg[:direction] }
        unknown = directions.keys - ["in", "out"]
        unless unknown.empty?
          raise Error, "#{method_name}: unsupported arg direction #{unknown.inspect}"
        end

        [
          method_name,
          Method.new(
            method_name,
            signature(directions["in"]),
            signature(directions["out"]),
          ),
        ]
      end
    end

    def scan_signals(body)
      body.scan(%r{<signal\s+([^>/]*?)\s*(?:/>|>(.*?)</signal>)}m).to_h do |attributes, args|
        signal_name = attribute(attributes, "name")
        [signal_name, Signal.new(signal_name, signature(scan_args(args.to_s)))]
      end
    end

    def scan_properties(body)
      body.scan(%r{<property\s+([^>/]*?)\s*(?:/>|>.*?</property>)}m).to_h do |(attributes)|
        property_name = attribute(attributes, "name")
        access = attribute(attributes, "access")
        unless %w[read write readwrite].include?(access)
          raise Error, "#{property_name}: unsupported access #{access.inspect}"
        end

        [
          property_name,
          Property.new(
            property_name,
            attribute(attributes, "type"),
            access != "write",
            access != "read",
          ),
        ]
      end
    end

    def scan_args(fragment)
      fragment.scan(%r{<arg\s+([^>/]*?)\s*/?>}m).map do |(attributes)|
        {
          type: attribute(attributes, "type"),
          # Signal args carry no direction; they are all outgoing.
          direction: attribute(attributes, "direction", required: false) || "out",
        }
      end
    end

    def attribute(attributes, key, required: true)
      value = attributes[/\b#{key}="([^"]*)"/, 1]
      raise Error, "missing #{key} in <... #{attributes}>" if value.nil? && required

      value
    end

    # [{type: "s"}, {type: "s"}] -> "(ss)". An empty tuple is "()", which is
    # how a method with no return value is described.
    def signature(args)
      "(#{Array(args).map { |arg| arg[:type] }.join})"
    end
  end

  # Builds a tuple variant, which GLib::Variant.new refuses to do.
  #
  # Each element is rendered with GLib::Variant#to_s (GLib's own text format,
  # correctly escaped) and the tuple is parsed against the signature taken from
  # the interface XML, so the wire types are exactly what was declared rather
  # than whatever the Ruby value happened to infer.
  def self.tuple(values, signature)
    return nil if signature == "()"

    elements = values.map { |value| variant_text(value) }
    # A one-element tuple needs the trailing comma: "(true,)", not "(true)".
    text = "(#{elements.join(", ")}#{elements.size == 1 ? "," : ""})"
    GLib::Variant.parse(text, signature)
  rescue StandardError => error
    raise Error, "cannot build #{signature} from #{values.inspect}: #{error.message}"
  end

  def self.variant_text(value)
    value.is_a?(GLib::Variant) ? value.to_s : GLib::Variant.new(value).to_s
  end
  private_class_method :variant_text

  # ruby-gnome hands closure arguments over already converted, so an incoming
  # "(sss)" arrives as a plain Array of Strings rather than as a GLib::Variant.
  # Accept either, so this does not depend on that behaviour staying put.
  def self.ruby_values(parameters)
    case parameters
    when nil then []
    when GLib::Variant then Array(parameters.value)
    when Array then parameters
    else [parameters]
    end
  end

  def self.ruby_value(value)
    value.is_a?(GLib::Variant) ? value.value : value
  end

  # Class-level DSL. `extend GDBus::Template` in the class you want exported.
  module Template
    # D-Bus names are CamelCase, Ruby names are snake_case: UpdateUi <->
    # update_ui, CssParserError <-> css_parser_error.
    def self.ruby_name(dbus_name)
      dbus_name
        .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
        .gsub(/([a-z\d])([A-Z])/, '\1_\2')
        .downcase
        .to_sym
    end

    def dbus_interface(xml, interface_name)
      @dbus_spec = InterfaceSpec.parse(xml, interface_name)
      # Kept alive deliberately: the interface info is owned by the node info,
      # and GLib will free it out from under the registration otherwise.
      @dbus_node_info = Gio::DBusNodeInfo.new(xml)
      @dbus_interface_info = @dbus_node_info.lookup_interface(interface_name)
      @dbus_methods = {}
      @dbus_properties = {}
    end

    def dbus_spec
      @dbus_spec || raise(Error, "#{self}: call dbus_interface first")
    end

    def dbus_interface_info
      dbus_spec && @dbus_interface_info
    end

    # Exported methods are opted in explicitly, so an ordinary helper method
    # can never be reached over the bus.
    #
    #   dbus_method def update_ui(content, target_id, original_id = "") ... end
    def dbus_method(ruby_name)
      dbus_name = find(dbus_spec.methods, ruby_name, "method")
      (@dbus_methods ||= {})[dbus_name] = ruby_name.to_sym
      ruby_name
    end

    # Defines an emitter: calling `window_open(true)` on the instance sends the
    # WindowOpen signal. Mirrors @DBusTemplate.Signal() in gdbus_ext.py, where
    # the decorated body is discarded and replaced by the emit.
    def dbus_signal(ruby_name)
      dbus_name = find(dbus_spec.signals, ruby_name, "signal")
      signature = dbus_spec.signals.fetch(dbus_name).signature

      define_method(ruby_name) do |*values|
        registration = GDBus.registration_for(self)
        next if registration.nil?

        registration.emit_signal(dbus_name, GDBus.tuple(values, signature))
      end
    end

    # Exposes an existing accessor pair. `dbus_property :color_scheme` reads
    # through #color_scheme and writes through #color_scheme=.
    def dbus_property(ruby_name)
      dbus_name = find(dbus_spec.properties, ruby_name, "property")
      (@dbus_properties ||= {})[dbus_name] = ruby_name.to_sym
    end

    def dbus_method_table
      @dbus_methods || {}
    end

    def dbus_property_table
      @dbus_properties || {}
    end

    private

    def find(table, ruby_name, kind)
      dbus_name = table.keys.find { |name| Template.ruby_name(name) == ruby_name.to_sym }
      return dbus_name if dbus_name

      raise Error,
            "#{self}: no #{kind} in #{dbus_spec.name} maps to #{ruby_name} " \
            "(have: #{table.keys.join(", ")})"
    end
  end

  # A live registration: the object, the connection it answers on, and the id
  # GLib gave us so it can be torn down again.
  class Registration
    attr_reader :connection, :object_path, :object

    def initialize(connection, object_path, object)
      @connection = connection
      @object_path = object_path
      @object = object
      @spec = object.class.dbus_spec
      @id = nil
    end

    def register
      @id = @connection.register_object(
        @object_path,
        @object.class.dbus_interface_info,
        method(:on_method_call).to_proc,
        method(:on_get_property).to_proc,
        method(:on_set_property).to_proc,
      )
      self
    end

    def unregister
      @connection.unregister_object(@id) if @id
      @id = nil
    end

    def emit_signal(dbus_name, parameters)
      # nil destination: broadcast. On the peer-to-peer connection the
      # previewer uses, Workbench is the only peer.
      @connection.emit_signal(nil, @object_path, @spec.name, dbus_name, parameters)
    end

    private

    def on_method_call(_connection, _sender, _path, _interface, dbus_name, parameters, invocation)
      ruby_name = @object.class.dbus_method_table[dbus_name]
      if ruby_name.nil?
        return invocation.return_dbus_error(
          "org.freedesktop.DBus.Error.UnknownMethod",
          "#{dbus_name} is not exported",
        )
      end

      arguments = GDBus.ruby_values(parameters)
      result = @object.public_send(ruby_name, *arguments)

      out_signature = @spec.methods.fetch(dbus_name).out_signature
      invocation.return_value(
        out_signature == "()" ? nil : GDBus.tuple([result], out_signature),
      )
    rescue StandardError => error
      # Without this the exception unwinds into C and takes the process down,
      # leaving Workbench waiting on a reply that never arrives.
      warn "#{dbus_name}: #{error.class}: #{error.message}"
      warn error.backtrace.join("\n")
      invocation.return_dbus_error(
        "re.sonny.Workbench.Error",
        "#{error.class}: #{error.message}",
      )
    end

    def on_get_property(_connection, _sender, _path, _interface, dbus_name)
      property = @spec.properties.fetch(dbus_name)
      ruby_name = @object.class.dbus_property_table.fetch(dbus_name)
      GLib::Variant.new(@object.public_send(ruby_name), property.signature)
    rescue StandardError => error
      warn "get #{dbus_name}: #{error.class}: #{error.message}"
      nil
    end

    def on_set_property(_connection, _sender, _path, _interface, dbus_name, value)
      ruby_name = @object.class.dbus_property_table.fetch(dbus_name)
      @object.public_send(:"#{ruby_name}=", GDBus.ruby_value(value))
      true
    rescue StandardError => error
      warn "set #{dbus_name}: #{error.class}: #{error.message}"
      false
    end
  end

  @registrations = {}

  def self.register_object(connection, object_path, object)
    registration = Registration.new(connection, object_path, object).register
    @registrations[object.object_id] = registration
  end

  def self.registration_for(object)
    @registrations[object.object_id]
  end

  def self.unregister_object(object)
    @registrations.delete(object.object_id)&.unregister
  end
end
