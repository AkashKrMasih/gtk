#!/usr/bin/env ruby
# frozen_string_literal: true

require 'open3'

module GtkLoader
  BINDING = begin
    require 'gtk3'
    :gtk3
  rescue LoadError
    require 'gir_ffi-gtk3'
    :gir_ffi
  end

  module_function

  def gtk3?
    BINDING == :gtk3
  end

  def accept?(response)
    sym = gtk3? ? response : Gtk::ResponseType.from_native(response)
    sym == :accept
  end

  # Returns array of paths or nil if cancelled.
  def choose_sources(parent, title: 'Select files or folders')
    dialog = build_open_dialog(parent, title)
    response = dialog.run
    return nil unless accept?(response)

    paths = dialog.filenames
    paths = paths.to_a unless paths.is_a?(Array)
    paths
  ensure
    dialog&.destroy
  end

  # Returns destination path or nil if cancelled.
  def choose_folder(parent, title: 'Choose destination folder')
    dialog = build_folder_dialog(parent, title)
    response = dialog.run
    return nil unless accept?(response)

    gtk3? ? dialog.filename : dialog.get_filename
  ensure
    dialog&.destroy
  end

  def build_open_dialog(parent, title)
    if gtk3?
      dialog = Gtk::FileChooserDialog.new(title: title, parent: parent, action: :open)
      dialog.select_multiple = true
      dialog.add_buttons(['Cancel', :cancel], ['Add', :accept])
    else
      dialog = Gtk::FileChooserDialog.new(title, parent, :open, [['Cancel', :cancel], ['Add', :accept]])
      dialog.select_multiple = true
    end
    dialog
  end

  def build_folder_dialog(parent, title)
    if gtk3?
      dialog = Gtk::FileChooserDialog.new(title: title, parent: parent, action: :select_folder)
      dialog.add_buttons(['Cancel', :cancel], ['Paste here', :accept])
    else
      dialog = Gtk::FileChooserDialog.new(
        title,
        parent,
        :select_folder,
        [['Cancel', :cancel], ['Paste here', :accept]]
      )
    end
    dialog
  end
end

class RsyncCopier
  RSYNC_BIN = ENV.fetch('RSYNC', '/usr/bin/rsync')

  class Error < StandardError; end

  def self.valid_rsync?
    File.executable?(RSYNC_BIN)
  end

  # Copies each source into +destination_dir+ (directory must exist).
  # Yields progress lines from rsync (stderr) when block given.
  def self.copy_all(sources, destination_dir, delete: false)
    raise Error, 'rsync not found' unless valid_rsync?

    dest = File.expand_path(destination_dir)
    raise Error, 'destination is not a directory' unless File.directory?(dest)

    sources = sources.map { |p| File.expand_path(p) }
    raise Error, 'no sources selected' if sources.empty?

    sources.each do |source|
      raise Error, "missing: #{source}" unless File.exist?(source)

      args = [
        RSYNC_BIN,
        '-a',
        '--human-readable',
        '--info=progress2',
        '--'
      ]
      args << '--delete' if delete
      args << source
      args << "#{dest}/"

      Open3.popen3(*args) do |_stdin, _stdout, stderr, wait_thr|
        stderr.each_line do |line|
          yield line.chomp if block_given?
        end
        status = wait_thr.value
        raise Error, "rsync failed for #{source} (exit #{status.exitstatus})" unless status.success?
      end
    end
  end
end

class MainWindow < Gtk::ApplicationWindow
  def initialize(app)
    super(app)
    self.title = 'Rsync Paste'
    set_default_size(520, 420)
    set_border_width(12)

    @enabled = true
    @clipboard_paths = []
    @busy = false

    build_ui
    signal_connect('destroy') { app.quit }
  end

  private

  def build_ui
    root = Gtk::Box.new(:vertical, 10)
    add(root)

    root.pack_start(power_row, expand: false, fill: true, padding: 0)
    root.pack_start(Gtk::Separator.new(:horizontal), expand: false, fill: true, padding: 4)
    root.pack_start(actions_row, expand: false, fill: true, padding: 0)
    root.pack_start(staging_label, expand: false, fill: true, padding: 0)

    scroll = Gtk::ScrolledWindow.new
    scroll.set_policy(:automatic, :automatic)
    scroll.set_min_content_height(120)
    @path_view = Gtk::TextView.new
    @path_view.editable = false
    @path_view.monospace = true
    scroll.add(@path_view)
    root.pack_start(scroll, expand: true, fill: true, padding: 0)

    root.pack_start(Gtk::Separator.new(:horizontal), expand: false, fill: true, padding: 4)
    root.pack_start(@progress_label = Gtk::Label.new('Ready'), expand: false, fill: true, padding: 0)
    root.pack_start(@progress_bar = Gtk::ProgressBar.new, expand: false, fill: true, padding: 0)

    scroll_log = Gtk::ScrolledWindow.new
    scroll_log.set_policy(:automatic, :automatic)
    scroll_log.set_min_content_height(80)
    @log_buffer = Gtk::TextBuffer.new
    log_view = Gtk::TextView.new(@log_buffer)
    log_view.editable = false
    log_view.monospace = true
    scroll_log.add(log_view)
    root.pack_start(scroll_log, expand: true, fill: true, padding: 0)

    refresh_path_view
    update_controls
  end

  def power_row
    row = Gtk::Box.new(:horizontal, 8)
    @power_switch = Gtk::Switch.new(active: true)
    @power_switch.signal_connect('notify::active') do |sw, _|
      @enabled = sw.active?
      append_log(@enabled ? 'App is ON — copy and paste enabled.' : 'App is OFF — paste disabled.')
      update_controls
    end
    label = Gtk::Label.new('App is ON')
    label.xalign = 0
    @power_switch.signal_connect('notify::active') { |sw, _| label.label = sw.active? ? 'App is ON' : 'App is OFF' }
    row.pack_start(label, expand: true, fill: true, padding: 0)
    row.pack_start(@power_switch, expand: false, fill: false, padding: 0)
    row
  end

  def actions_row
    row = Gtk::Box.new(:horizontal, 8)
    @copy_btn = Gtk::Button.new(label: 'Copy…')
    @copy_btn.signal_connect('clicked') { on_copy }
    @paste_btn = Gtk::Button.new(label: 'Paste to…')
    @paste_btn.signal_connect('clicked') { on_paste }
    @clear_btn = Gtk::Button.new(label: 'Clear staging')
    @clear_btn.signal_connect('clicked') { on_clear }
    row.pack_start(@copy_btn, expand: true, fill: true, padding: 0)
    row.pack_start(@paste_btn, expand: true, fill: true, padding: 0)
    row.pack_start(@clear_btn, expand: false, fill: false, padding: 0)
    row
  end

  def staging_label
    lbl = Gtk::Label.new('Staged paths (copied with rsync on paste):')
    lbl.xalign = 0
    lbl
  end

  def on_copy
    paths = GtkLoader.choose_sources(self, title: 'Select files or folders to copy')
    return unless paths

    paths.each { |path| @clipboard_paths << path unless @clipboard_paths.include?(path) }
    refresh_path_view
    append_log("Staged #{paths.size} item(s).")
  end

  def on_paste
    return unless @enabled
    return if @clipboard_paths.empty?

    dest = GtkLoader.choose_folder(self, title: 'Choose destination folder')
    start_paste(dest) if dest
  end

  def on_clear
    @clipboard_paths.clear
    refresh_path_view
    append_log('Staging cleared.')
  end

  def start_paste(destination)
    return if @busy

    @busy = true
    update_controls
    @progress_bar.fraction = 0
    @progress_label.label = 'Running rsync…'
    append_log("Pasting into #{destination}")

    sources = @clipboard_paths.dup

    Thread.new do
      begin
        RsyncCopier.copy_all(sources, destination) do |line|
          GLib::Idle.add do
            append_log(line)
            parse_progress(line)
            false
          end
        end
        GLib::Idle.add do
          finish_paste(success: true, destination: destination)
          false
        end
      rescue RsyncCopier::Error => e
        GLib::Idle.add do
          finish_paste(success: false, message: e.message)
          false
        end
      end
    end
  end

  def parse_progress(line)
    # rsync --info=progress2: e.g. "  1,234,567  45%   12.34MB/s    0:00:01"
    if line =~ /(\d+)\s*%/
      @progress_bar.fraction = Regexp.last_match(1).to_f / 100.0
      @progress_label.label = line
    end
  end

  def finish_paste(success:, destination: nil, message: nil)
    @busy = false
    update_controls
    if success
      @progress_bar.fraction = 1.0
      @progress_label.label = "Done — pasted to #{destination}"
      append_log('Paste completed.')
    else
      @progress_bar.fraction = 0
      @progress_label.label = 'Paste failed'
      append_log("Error: #{message}")
      show_error(message)
    end
  end

  def show_error(message)
    dialog = Gtk::MessageDialog.new(
      parent: self,
      flags: :destroy_with_parent,
      type: :error,
      buttons: :close,
      message: message
    )
    dialog.run
    dialog.destroy
  end

  def refresh_path_view
    text = @clipboard_paths.empty? ? '(nothing staged)' : @clipboard_paths.join("\n")
    @path_view.buffer.text = text
  end

  def append_log(line)
    end_iter = @log_buffer.end_iter
    @log_buffer.insert(end_iter, "#{line}\n")
  end

  def update_controls
    sensitive = !@busy
    @copy_btn.sensitive = sensitive
    @clear_btn.sensitive = sensitive
    @paste_btn.sensitive = sensitive && @enabled && !@clipboard_paths.empty?
    @power_switch.sensitive = !@busy
  end
end

unless RsyncCopier.valid_rsync?
  warn "rsync not found at #{RsyncCopier::RSYNC_BIN}. Install rsync or set RSYNC."
  exit 1
end

app = Gtk::Application.new('com.example.RsyncPaste', :flags_none)
app.signal_connect('activate') do |application|
  window = MainWindow.new(application)
  window.show
end

status = app.run([$PROGRAM_NAME] + ARGV)
exit(status)