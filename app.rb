#!/usr/bin/env ruby
# frozen_string_literal: true

# Rsync Paste — GTK 4 version (Ubuntu 24.04, gem "gtk4")

require 'open3'
require 'gtk4'

# ---------------------------------------------------------------------------
# File / folder pickers (GTK 4: no dialog.run, so everything is callback based)
# ---------------------------------------------------------------------------
module Pickers
  module_function

  def accepted?(response)
    value = response.respond_to?(:nick) ? response.nick : response
    %w[accept -3].include?(value.to_s)
  end

  # Calls the block with an Array of paths (or never, if cancelled).
  def choose_sources(parent, title: 'Select files or folders', folders: false, &on_done)
    action  = folders ? :select_folder : :open
    chooser = Gtk::FileChooserNative.new(title, parent, action, 'Add', 'Cancel')
    chooser.select_multiple = true
    run(chooser) do
      list = chooser.files
      paths = (0...list.n_items).map { |i| list.get_item(i).path }
      on_done.call(paths)
    end
  end

  # Calls the block with a destination path (or never, if cancelled).
  def choose_folder(parent, title: 'Choose destination folder', &on_done)
    chooser = Gtk::FileChooserNative.new(title, parent, :select_folder, 'Paste here', 'Cancel')
    run(chooser) { on_done.call(chooser.file.path) }
  end

  def run(chooser)
    # Keep a reference so the native dialog is not garbage collected while open.
    (@open_choosers ||= []) << chooser
    chooser.signal_connect('response') do |dlg, response|
      yield if accepted?(response)
      @open_choosers.delete(dlg)
      dlg.destroy
    end
    chooser.show
  end
end

# ---------------------------------------------------------------------------
# rsync wrapper
# ---------------------------------------------------------------------------
class RsyncCopier
  RSYNC_BIN = ENV.fetch('RSYNC', '/usr/bin/rsync')

  class Error < StandardError; end

  def self.valid_rsync?
    File.executable?(RSYNC_BIN)
  end

  # Copies each source into +destination_dir+ (directory must exist).
  # Yields progress lines from rsync when a block is given.
  def self.copy_all(sources, destination_dir, delete: false)
    raise Error, 'rsync not found' unless valid_rsync?

    dest = File.expand_path(destination_dir)
    raise Error, 'destination is not a directory' unless File.directory?(dest)

    sources = sources.map { |p| File.expand_path(p) }
    raise Error, 'no sources selected' if sources.empty?

    sources.each do |source|
      raise Error, "missing: #{source}" unless File.exist?(source)

      # Options must come BEFORE "--", otherwise rsync treats them as file names.
      args = [RSYNC_BIN, '-a', '--human-readable', '--info=progress2', '--no-inc-recursive']
      args << '--delete' if delete
      args += ['--', source, "#{dest}/"]

      # popen2e merges stdout+stderr. rsync writes progress to stdout and
      # separates updates with "\r", so read with a "\r" separator.
      Open3.popen2e(*args) do |_stdin, out, wait_thr|
        out.each_line("\r") do |chunk|
          chunk.split(/[\r\n]+/).each do |line|
            yield line unless line.strip.empty? || !block_given?
          end
        end
        status = wait_thr.value
        raise Error, "rsync failed for #{source} (exit #{status.exitstatus})" unless status.success?
      end
    end
  end
end

# ---------------------------------------------------------------------------
# Main window
# ---------------------------------------------------------------------------
class MainWindow < Gtk::ApplicationWindow
  def initialize(app)
    super(app)
    self.title = 'Rsync Paste'
    set_default_size(520, 420)

    @enabled         = true
    @clipboard_paths = []
    @busy            = false

    build_ui
  end

  private

  def build_ui
    root = Gtk::Box.new(:vertical, 10)
    root.margin_top = root.margin_bottom = root.margin_start = root.margin_end = 12
    self.child = root

    root.append(power_row)
    root.append(Gtk::Separator.new(:horizontal))
    root.append(actions_row)
    root.append(staging_label)

    scroll = Gtk::ScrolledWindow.new
    scroll.set_policy(:automatic, :automatic)
    scroll.min_content_height = 120
    scroll.vexpand = true
    @path_view = Gtk::TextView.new
    @path_view.editable  = false
    @path_view.monospace = true
    scroll.child = @path_view
    root.append(scroll)

    root.append(Gtk::Separator.new(:horizontal))
    @progress_label = Gtk::Label.new('Ready')
    @progress_label.xalign = 0
    @progress_label.ellipsize = :end
    root.append(@progress_label)
    @progress_bar = Gtk::ProgressBar.new
    root.append(@progress_bar)

    scroll_log = Gtk::ScrolledWindow.new
    scroll_log.set_policy(:automatic, :automatic)
    scroll_log.min_content_height = 80
    scroll_log.vexpand = true
    @log_view = Gtk::TextView.new
    @log_view.editable  = false
    @log_view.monospace = true
    @log_buffer = @log_view.buffer
    @end_mark   = @log_buffer.create_mark(nil, @log_buffer.end_iter, false)
    scroll_log.child = @log_view
    root.append(scroll_log)

    refresh_path_view
    update_controls
  end

  def power_row
    row = Gtk::Box.new(:horizontal, 8)

    label = Gtk::Label.new('App is ON')
    label.xalign = 0
    label.hexpand = true

    @power_switch = Gtk::Switch.new
    @power_switch.active = true
    @power_switch.valign = :center
    @power_switch.signal_connect('notify::active') do |sw, _|
      @enabled = sw.active?
      label.label = @enabled ? 'App is ON' : 'App is OFF'
      append_log(@enabled ? 'App is ON — copy and paste enabled.' : 'App is OFF — paste disabled.')
      update_controls
    end

    row.append(label)
    row.append(@power_switch)
    row
  end

  def actions_row
    row = Gtk::Box.new(:horizontal, 8)

    @copy_btn = Gtk::Button.new
    @copy_btn.label = 'Copy files…'
    @copy_btn.hexpand = true
    @copy_btn.signal_connect('clicked') { on_copy }

    @copy_folder_btn = Gtk::Button.new
    @copy_folder_btn.label = 'Copy folders…'
    @copy_folder_btn.hexpand = true
    @copy_folder_btn.signal_connect('clicked') { on_copy(folders: true) }

    @paste_btn = Gtk::Button.new
    @paste_btn.label = 'Paste to…'
    @paste_btn.hexpand = true
    @paste_btn.signal_connect('clicked') { on_paste }

    @clear_btn = Gtk::Button.new
    @clear_btn.label = 'Clear staging'
    @clear_btn.signal_connect('clicked') { on_clear }

    row.append(@copy_btn)
    row.append(@copy_folder_btn)
    row.append(@paste_btn)
    row.append(@clear_btn)
    row
  end

  def staging_label
    lbl = Gtk::Label.new('Staged paths (copied with rsync on paste):')
    lbl.xalign = 0
    lbl
  end

  def on_copy(folders: false)
    title = folders ? 'Select folders to copy' : 'Select files to copy'
    Pickers.choose_sources(self, title: title, folders: folders) do |paths|
      paths.each { |path| @clipboard_paths << path unless @clipboard_paths.include?(path) }
      refresh_path_view
      update_controls
      append_log("Staged #{paths.size} item(s).")
    end
  end

  def on_paste
    return unless @enabled
    return if @clipboard_paths.empty?

    Pickers.choose_folder(self, title: 'Choose destination folder') do |dest|
      start_paste(dest)
    end
  end

  def on_clear
    @clipboard_paths.clear
    refresh_path_view
    update_controls
    append_log('Staging cleared.')
  end

  def start_paste(destination)
    return if @busy

    @busy = true
    update_controls
    @progress_bar.fraction = 0
    @progress_label.label  = 'Running rsync…'
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
      rescue StandardError => e
        GLib::Idle.add do
          finish_paste(success: false, message: e.message)
          false
        end
      end
    end
  end

  def parse_progress(line)
    # rsync --info=progress2: e.g. "  1,234,567  45%   12.34MB/s    0:00:01"
    return unless (m = line.match(/(\d+)\s*%/))

    @progress_bar.fraction = m[1].to_f / 100.0
    @progress_label.label  = line.strip
  end

  def finish_paste(success:, destination: nil, message: nil)
    @busy = false
    update_controls
    if success
      @progress_bar.fraction = 1.0
      @progress_label.label  = "Done — pasted to #{destination}"
      append_log('Paste completed.')
    else
      @progress_bar.fraction = 0
      @progress_label.label  = 'Paste failed'
      append_log("Error: #{message}")
      show_error(message)
    end
  end

  def show_error(message)
    alert = Gtk::AlertDialog.new
    alert.message = 'Paste failed'
    alert.detail  = message
    alert.modal   = true
    alert.show(self)
  end

  def refresh_path_view
    @path_view.buffer.text = @clipboard_paths.empty? ? '(nothing staged)' : @clipboard_paths.join("\n")
  end

  def append_log(line)
    @log_buffer.insert(@log_buffer.end_iter, "#{line}\n")
    # keep the newest line visible (the mark has right gravity, so it stays at the end)
    @log_view.scroll_to_mark(@end_mark, 0.0, false, 0.0, 0.0)
  end

  def update_controls
    sensitive = !@busy
    @copy_btn.sensitive        = sensitive
    @copy_folder_btn.sensitive = sensitive
    @clear_btn.sensitive       = sensitive
    @paste_btn.sensitive    = sensitive && @enabled && !@clipboard_paths.empty?
    @power_switch.sensitive = sensitive
  end
end

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
unless RsyncCopier.valid_rsync?
  warn "rsync not found at #{RsyncCopier::RSYNC_BIN}. Install rsync or set RSYNC."
  exit 1
end

app = Gtk::Application.new('com.example.RsyncPaste', :flags_none)
app.signal_connect('activate') do |application|
  window = MainWindow.new(application)
  window.present # GTK 4: children are shown automatically, no show_all
end

exit(app.run([$PROGRAM_NAME] + ARGV))