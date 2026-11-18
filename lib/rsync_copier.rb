# frozen_string_literal: true

require 'open3'
require 'fileutils'

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