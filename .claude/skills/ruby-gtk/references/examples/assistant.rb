require 'gtk4'

class AssistantDemo
  def build
    app.tap do
      app.signal_connect('activate') do
        app.add_window(assistant)

        assistant.tap do |ast|
          ast.signal_connect('cancel') { ast.destroy }
          ast.signal_connect('close') { ast.destroy }
          ast.signal_connect('apply') { on_apply }
          ast.signal_connect('prepare') { |_, page| on_prepare(page) }

          # Page 1: Entry (must fill to continue)
          page1_box.tap do |box|
            box.append(page1_label)
            box.append(page1_entry)

            page1_entry.tap do |entry|
              entry.signal_connect('changed') do
                ast.set_page_complete(box, !entry.text.to_s.empty?)
              end
            end

            ast.append_page(box)
            ast.set_page_title(box, 'Page 1')
            ast.set_page_type(box, :intro)
          end

          # Page 2: Optional checkbox
          page2_box.tap do |box|
            box.append(page2_check)

            ast.append_page(box)
            ast.set_page_title(box, 'Page 2')
            ast.set_page_complete(box, true)
          end

          # Page 3: Confirmation
          page3_label.tap do |label|
            ast.append_page(label)
            ast.set_page_title(label, 'Confirmation')
            ast.set_page_type(label, :confirm)
            ast.set_page_complete(label, true)
          end

          # Page 4: Progress
          progress_bar.tap do |bar|
            ast.append_page(bar)
            ast.set_page_title(bar, 'Applying changes')
            ast.set_page_type(bar, :progress)
            ast.set_page_complete(bar, false)
          end

          ast.present
        end
      end
    end
  end

  def app = @app ||= Gtk::Application.new('org.example.assistant', :default_flags)
  def page1_label = @page1_label ||= Gtk::Label.new('You must fill out this entry to continue:')
  def page3_label = @page3_label ||= Gtk::Label.new("This is a confirmation page, press 'Apply' to apply changes")

  def assistant
    @assistant ||= Gtk::Assistant.new.tap do |ast|
      ast.default_height = 300
    end
  end

  def page1_box
    @page1_box ||= Gtk::Box.new(:horizontal, 12).tap do |box|
      box.margin_start = 12
      box.margin_end = 12
      box.margin_top = 12
      box.margin_bottom = 12
    end
  end

  def page1_entry
    @page1_entry ||= Gtk::Entry.new.tap do |entry|
      entry.activates_default = true
      entry.valign = :center
    end
  end

  def page2_box
    @page2_box ||= Gtk::Box.new(:horizontal, 12).tap do |box|
      box.margin_start = 12
      box.margin_end = 12
      box.margin_top = 12
      box.margin_bottom = 12
    end
  end

  def page2_check
    @page2_check ||= Gtk::CheckButton.new(
      'This is optional data, you may continue even if you do not check this'
    ).tap do |check|
      check.valign = :center
    end
  end

  def progress_bar
    @progress_bar ||= Gtk::ProgressBar.new.tap do |bar|
      bar.halign = :fill
      bar.valign = :center
      bar.hexpand = true
      bar.margin_start = 40
      bar.margin_end = 40
    end
  end

  def on_prepare(page)
    assistant.title = "Sample assistant (#{assistant.current_page + 1} of #{assistant.n_pages})"
    assistant.commit if assistant.current_page == 3
  end

  def on_apply
    GLib::Timeout.add(100) do
      (progress_bar.fraction + 0.05).then do |fraction|
        if fraction < 1.0
          progress_bar.fraction = fraction
          GLib::Source::CONTINUE
        else
          assistant.destroy
          GLib::Source::REMOVE
        end
      end
    end
  end
end

AssistantDemo.new.build.run
