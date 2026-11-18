#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'lib/gtk_loader'
require_relative 'lib/main_window'

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