#!/usr/bin/env ruby

# Runs Puppet, while printing a progress bar showing the status of the run in
# terms of resources evaluated of the entire catalog.
#
# Tried using a pipe between this process and Puppet, but it failed as the
# pipe fd kept getting closed in the child, even though FD_CLOEXEC didn't
# appear to be set.  (Maybe MRI or Puppet closing it.)
#
# Tried using a FIFO, but a mkfifo wrapper is missing from Ruby.
#
# Ended up using a UNIX domain socket.

require 'rubygems'
require 'ruby-progressbar'
require 'socket'
require 'tmpdir'

nobars = false

Dir.mktmpdir do |temp|
  socket_path = File.join(temp, 'progress.sock')
  server = UNIXServer.new(socket_path)

  pid = fork do
    ENV['RUBYLIB'] = ["#{Dir.pwd}/lib", ENV['RUBYLIB']].join(File::PATH_SEPARATOR)
    ENV['KAFO_PROGRESS'] = socket_path
    $stdout.reopen(File.open(File.join('/tmp', 'puppet.out'), 'w'))
    $stderr.reopen(File.open(File.join('/tmp', 'puppet.err'), 'w'))
    #$stdout.reopen(File.open(File.join(temp, 'puppet.out'), 'w'))
    #$stderr.reopen(File.open(File.join(temp, 'puppet.err'), 'w'))
    Process.exec 'puppet', 'apply', '-d', '--trace', 'manifest.pp'
    exit!(0)
  end

  progress_bar = nil
  socket = server.accept
  while (result = socket.gets)
    if result =~ /^START (\d+)/ && !nobars
      progress_bar = ProgressBar.create(:total => $1.to_i, :format => '%t: |%B| %e', :smoothing => 0.6)
    elsif result =~ /^RESOURCE /
      progress_bar.increment if progress_bar && progress_bar.progress < progress_bar.total
    end
  end
  Process.wait(pid)
  progress_bar.finish if progress_bar && progress_bar.progress < progress_bar.total

  socket.close
  server.close
end
