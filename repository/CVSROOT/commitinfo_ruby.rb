#!/usr/bin/env ruby
#
# CVS commit mail script (pre-commit accumulation script)
# This script is run before each commit.
#
# Use only args, not STDIN.
# ARG0 : $CVSROOT
# ARG1 : CVS user name
# ARG2 : absolute path of the module
# ARG3 : file1
# ARG4 : file2
# ..
#
# $Idaemons: /home/cvs/cvsmailer/commitinfo.rb,v 1.4 2001/01/19 17:22:53 knu Exp $
# $devId: commitinfo.rb,v 1.8 2001/01/31 14:58:24 knu Exp $
# $Id: commitinfo_ruby.rb,v 1.5 2001/01/31 15:07:20 knu Exp $
#

if ARGV.size < 4
  puts "Usage: #{$0} CVSROOT USER modulepath file1 [file2...]"
  exit 1	# No way!
end

$cvsroot, $cvsuser, $modulepath, *$cvsfiles = *ARGV

$cvsroot.tr_s!('/', '/')
$modulepath.tr_s!('/', '/')

$modulename = $modulepath.sub(/^#{Regexp.quote($cvsroot)}/, '')

$aclfile = "#{$cvsroot}/CVSROOT/acl"

require "socket"
$hostname = Socket.gethostbyname(Socket.gethostname)[0]

# ACL check:
$:.unshift "#{$cvsroot}/CVSROOT"
require "cvsacl"

if File.exist?($aclfile)
  if !check_acl($aclfile, $hostname, $cvsuser, $modulename)
    exit 1	# No way!
  end
end

# append a line to a file
def appendline(fn, s)
  File.open(fn, "a+").puts s
end

savefile = sprintf("/tmp/commitinfo.%s.%d", $cvsuser, Process.getpgrp())

appendline savefile, "#{$cvsroot} #{$modulepath} #{$cvsfiles.join(' ')}"

exit 0		# Let's do it!

# END OF THE SCRIPT
