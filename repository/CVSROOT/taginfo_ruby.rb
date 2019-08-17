#!/usr/bin/env ruby
#
# CVS tag info script
# This script is run before each tag/rtag.
#
# Use only args, not STDIN.
# ARG0 : $CVSROOT
# ARG1 : CVS user name
# ARG2 : tagname
# ARG3 : operation ("add" for tag, "mov" for tag -F, and "del" for tag -d)
# ARG4 : absolute path of the module
# ARG5 : file1
# ARG6 : revision1
# ..
#
# $devId: taginfo.rb,v 1.5 2001/02/03 15:53:30 knu Exp $
# $Id: taginfo_ruby.rb,v 1.6 2001/05/24 08:03:26 knu Exp $
#

if ARGV.size < 5
  puts "Usage: #{$0} CVSROOT USER tagname operation modulepath [file1 rev1 file2 rev2 ...]"
  exit 1	# No way!
end

$cvsroot, $cvsuser, $tagname, $operation, $modulepath, *$cvsfilerevs = *ARGV

$cvsroot.tr_s!('/', '/')
$modulepath.tr_s!('/', '/')

$modulename = $modulepath.sub(/^#{Regexp.quote($cvsroot)}/, '')

$aclfile = "#{$cvsroot}/CVSROOT/acl"

require "socket"
$hostname = Socket.gethostbyname(Socket.gethostname)[0]

# acl check:
$:.unshift "#{$cvsroot}/CVSROOT"
require "cvsacl"

if File.exist?($aclfile)
  if !check_acl($aclfile, $hostname, $cvsuser, $modulename)
    exit 1	# No way!
  end
end

exit 0		# Let's do it!

# END OF THE SCRIPT
