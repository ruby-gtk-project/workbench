require 'gtk4'

class Message
  attr_accessor :id, :sender_name, :sender_nick, :message, :time,
                :reply_to, :resent_by, :n_favorites, :n_reshares

  def self.parse(line)
    line.split('|').then do |parts|
      new.tap do |msg|
        msg.id = parts[0].to_i
        msg.sender_name = parts[1]
        msg.sender_nick = parts[2]
        msg.message = parts[3]
        msg.time = Time.at(parts[4].to_i)
        msg.reply_to = parts[5]&.to_i
        msg.resent_by = parts[6]&.empty? ? nil : parts[6]
        msg.n_favorites = parts[7]&.to_i || 0
        msg.n_reshares = parts[8]&.to_i || 0
      end
    end
  end

  def formatted_short_time
    time.strftime('%e %b %y')
  end

  def formatted_detailed_time
    time.strftime('%X - %e %b %Y')
  end
end

class MessageRow
  attr_reader :message

  def initialize(message)
    @message = message
    @expanded = false
  end

  def build
    @build ||= row.tap do |r|
      r.child = grid

      grid.tap do |g|
        g.attach(avatar_image, 0, 0, 1, 5)
        g.attach(header_box, 1, 0, 1, 1)
        g.attach(content_label, 1, 1, 1, 1)
        g.attach(resent_box, 1, 2, 1, 1)
        g.attach(buttons_box, 1, 3, 1, 1)
        g.attach(details_revealer, 1, 4, 1, 1)

        header_box.tap do |box|
          box.append(name_button)
          box.append(nick_label)
          box.append(time_label)
        end

        resent_box.tap do |box|
          box.append(resent_icon)
          box.append(resent_caption)
          box.append(resent_by_button)
        end

        buttons_box.tap do |box|
          box.append(expand_button)
          box.append(extra_buttons_box)

          expand_button.tap do |btn|
            btn.signal_connect('clicked') { toggle_expand }
          end

          extra_buttons_box.tap do |ebox|
            ebox.append(reply_button)
            ebox.append(reshare_button)
            ebox.append(favorite_button)
            ebox.append(more_button)

            reshare_button.tap do |btn|
              btn.signal_connect('clicked') { on_reshare }
            end

            favorite_button.tap do |btn|
              btn.signal_connect('clicked') { on_favorite }
            end
          end
        end

        details_revealer.tap do |rev|
          rev.child = details_box

          details_box.tap do |box|
            box.append(stats_box)
            box.append(detailed_time_box)

            stats_box.tap do |sbox|
              sbox.append(reshares_label)
              sbox.append(favorites_label)
            end

            detailed_time_box.tap do |tbox|
              tbox.append(detailed_time_label)
              tbox.append(details_button)
            end
          end
        end
      end

      r.signal_connect('state-flags-changed') do
        r.state_flags.then do |flags|
          extra_buttons_box.visible = flags.prelight? || flags.selected?
        end
      end
    end
  end

  def row = @row ||= Gtk::ListBoxRow.new
  def details_box = @details_box ||= Gtk::Box.new(:vertical, 0)
  def buttons_box = @buttons_box ||= Gtk::Box.new(:horizontal, 6)
  def detailed_time_box = @detailed_time_box ||= Gtk::Box.new(:horizontal, 0)
  def resent_icon = @resent_icon ||= Gtk::Image.new(icon_name: 'media-playlist-repeat')
  def resent_caption = @resent_caption ||= Gtk::Label.new('Resent by')
  def details_revealer = @details_revealer ||= Gtk::Revealer.new

  def more_button
    @more_button ||= Gtk::MenuButton.new.tap do |btn|
      btn.label = 'More...'
      btn.has_frame = false
      btn.menu_model = more_menu
    end
  end

  def grid
    @grid ||= Gtk::Grid.new.tap do |g|
      g.hexpand = true
    end
  end

  def avatar_image
    @avatar_image ||= Gtk::Image.new.tap do |img|
      img.set_size_request(32, 32)
      img.halign = :center
      img.valign = :start
      img.margin_top = 8
      img.margin_bottom = 8
      img.margin_start = 8
      img.margin_end = 8
      img.icon_size = :large
      img.icon_name = message.sender_nick == 'GTKtoolkit' ? 'org.gtk.Demo4' : 'avatar-default-symbolic'
    end
  end

  def header_box
    @header_box ||= Gtk::Box.new(:horizontal, 0).tap do |box|
      box.hexpand = true
    end
  end

  def name_button
    @name_button ||= Gtk::Button.new.tap do |btn|
      btn.has_frame = false
      btn.valign = :baseline
      btn.child = name_button_label
    end
  end

  def name_button_label
    @name_button_label ||= Gtk::Label.new(message.sender_name).tap do |lbl|
      lbl.attributes = Pango::AttrList.new.tap { |a| a.insert(Pango::AttrWeight.new(:bold)) }
      lbl.valign = :baseline
    end
  end

  def nick_label
    @nick_label ||= Gtk::Label.new("@#{message.sender_nick}").tap do |lbl|
      lbl.valign = :baseline
      lbl.add_css_class('dim-label')
    end
  end

  def time_label
    @time_label ||= Gtk::Label.new(message.formatted_short_time).tap do |lbl|
      lbl.hexpand = true
      lbl.xalign = 1
      lbl.valign = :baseline
      lbl.add_css_class('dim-label')
    end
  end

  def content_label
    @content_label ||= Gtk::Label.new(message.message).tap do |lbl|
      lbl.halign = :start
      lbl.valign = :start
      lbl.xalign = 0
      lbl.yalign = 0
      lbl.wrap = true
    end
  end

  def resent_box = @resent_box ||= Gtk::Box.new(:horizontal, 0)

  def resent_by_button
    @resent_by_button ||= Gtk::LinkButton.new('').tap do |btn|
      btn.label = message.resent_by.to_s
      btn.has_frame = false
      btn.uri = 'http://www.gtk.org'
    end
  end

  def expand_button
    @expand_button ||= Gtk::Button.new.tap do |btn|
      btn.label = 'Expand'
      btn.has_frame = false
    end
  end

  def extra_buttons_box
    @extra_buttons_box ||= Gtk::Box.new(:horizontal, 6).tap do |ebox|
      ebox.visible = false
    end
  end

  def reply_button
    @reply_button ||= Gtk::Button.new.tap do |btn|
      btn.label = 'Reply'
      btn.has_frame = false
    end
  end

  def reshare_button
    @reshare_button ||= Gtk::Button.new.tap do |btn|
      btn.label = 'Reshare'
      btn.has_frame = false
    end
  end

  def favorite_button
    @favorite_button ||= Gtk::Button.new.tap do |btn|
      btn.label = 'Favorite'
      btn.has_frame = false
    end
  end

  def stats_box
    @stats_box ||= Gtk::Box.new(:horizontal, 8).tap do |sbox|
      sbox.margin_top = 2
      sbox.margin_bottom = 2
    end
  end

  def reshares_label
    @reshares_label ||= Gtk::Label.new.tap do |lbl|
      lbl.use_markup = true
      lbl.label = "<b>#{message.n_reshares}</b>\nReshares"
    end
  end

  def favorites_label
    @favorites_label ||= Gtk::Label.new.tap do |lbl|
      lbl.use_markup = true
      lbl.label = "<b>#{message.n_favorites}</b>\nFavorites"
    end
  end

  def detailed_time_label
    @detailed_time_label ||= Gtk::Label.new(message.formatted_detailed_time).tap do |lbl|
      lbl.add_css_class('dim-label')
    end
  end

  def details_button
    @details_button ||= Gtk::Button.new.tap do |btn|
      btn.label = 'Details'
      btn.has_frame = false
      btn.add_css_class('dim-label')
    end
  end

  def more_menu
    @more_menu ||= Gio::Menu.new.tap do |menu|
      Gio::Menu.new.tap do |section|
        section.append('Email message', nil)
        section.append('Embed message', nil)
        menu.append_section(nil, section)
      end
    end
  end

  def toggle_expand
    @expanded = !@expanded
    details_revealer.reveal_child = @expanded
    expand_button.label = @expanded ? 'Hide' : 'Expand'
  end

  def on_reshare
    message.n_reshares += 1
    update_stats
  end

  def on_favorite
    message.n_favorites += 1
    update_stats
  end

  def update_stats
    reshares_label.label = "<b>#{message.n_reshares}</b>\nReshares"
    favorites_label.label = "<b>#{message.n_favorites}</b>\nFavorites"
  end
end

class ListBoxDemo
  MESSAGES_DATA = <<~DATA
    1|GTK+ and friends|GTKtoolkit|@breizhodrome yeah, that's for the OpenGL support that has been added recently|1416751697|0||2|1
    2|Emmanuele Bassi|ebassi|RT @ebassi: embloggeration happened: http://t.co/9ukkNuSzuc — help out supporting GL on windows and macos in GTK+ 3.16.|1416086824|0|GTKtoolkit|0|9
    3|Matthew Waters|ystreet00|RT @ystreet00: .@GTKtoolkit + @gstreamer integration using the new #gtk #opengl support https://t.co/IeBpFjbjes http://t.co/WptPHCfFIb|1416086780|0|GTKtoolkit|0|13
    4|Emmanuele Bassi|ebassi|RT @ebassi: embloggeration happened — OpenGL integration lands in GTK+ — http://t.co/sUGwcvZhRg|1413214719|0|GTKtoolkit|0|8
    5|Allan Day|allanday|RT @allanday: New Human Interface Guidelines coming for @gnome and @GTKtoolkit . http://t.co/SMNndyo6rl|1408615736|0|GTKtoolkit|0|12
    6|Christian Hergert|hergertme|RT @hergertme: being able to set opacity on an individual widget in gtk ... you've come a long way since 2.x days.|1408601183|0|GTKtoolkit|0|2
    7|Richard Brown|sysrich|RT @sysrich: hmm, good thing Iike eating with chopsticks #GUADEC http://t.co/7aG9CYpdZg|1406543731|0|GTKtoolkit|0|82
    8|Javier Jardón|jjardon|RT @jjardon: #GNOME 3.13.4 has just been released from Strasbourg, this year #GUADEC city. Enjoy! https://t.co/hgHDVOWvRC|1406303072|0|GTKtoolkit|0|6
    9|GNOME|gnome|RT @gnome: This year's @guadec schedule has been published. Lots of great talks on there, as usual. https://t.co/rpGPxIRCuB|1405929795|0|GTKtoolkit|0|20
    10|GTK+ and friends|GTKtoolkit|New features of GtkInspector : http://t.co/EOgcv1lh8D #gtk #gtk3|1402076874|0||2|3
  DATA

  def build
    app.tap do
      app.signal_connect('activate') do
        app.add_window(window)

        window.tap do |win|
          win.title = 'List Box — Complex'
          win.set_default_size(400, 600)
          win.child = main_box
        end

        main_box.tap do |box|
          box.append(header_label)
          box.append(scrolled_window)

          scrolled_window.tap do |sw|
            sw.child = list_box

            list_box.tap do |lb|
              lb.set_sort_func do |row_a, row_b|
                [message_rows[row_a], message_rows[row_b]].then do |a, b|
                  a && b ? b.message.time <=> a.message.time : 0
                end
              end

              lb.signal_connect('row-activated') do |_, row|
                message_rows[row]&.toggle_expand
              end

              messages.each do |msg|
                MessageRow.new(msg).tap do |msg_row|
                  msg_row.build.tap do |gtk_row|
                    message_rows[gtk_row] = msg_row
                    lb.append(gtk_row)
                  end
                end
              end
            end
          end
        end

        window.present
      end
    end
  end

  def app = @app ||= Gtk::Application.new('org.example.listbox', :default_flags)
  def window = @window ||= Gtk::Window.new
  def header_label = @header_label ||= Gtk::Label.new('Messages from GTK and friends')
  def message_rows = @message_rows ||= {}

  def main_box = @main_box ||= Gtk::Box.new(:vertical, 12)

  def scrolled_window
    @scrolled_window ||= Gtk::ScrolledWindow.new.tap do |sw|
      sw.hscrollbar_policy = :never
      sw.vscrollbar_policy = :automatic
      sw.vexpand = true
    end
  end

  def list_box
    @list_box ||= Gtk::ListBox.new.tap do |lb|
      lb.activate_on_single_click = false
    end
  end

  def messages
    @messages ||= MESSAGES_DATA.strip.split("\n").map { |line| Message.parse(line) }
  end
end

ListBoxDemo.new.build.run
