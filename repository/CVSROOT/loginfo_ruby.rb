#!/usr/bin/env ruby
#
# CVS commit mail script (loginfo)
#
# $Idaemons: /home/cvs/cvsmailer/loginfo.rb,v 1.3 2001/01/15 19:42:12 knu Exp $
# $devId: loginfo.rb,v 1.12 2001/06/06 12:46:24 knu Exp $
# $Id: loginfo_ruby.rb,v 1.12 2001/06/06 12:47:34 knu Exp $
#

MYNAME = File.basename($0)

require 'parsearg'
require 'socket'

def time2str(tm)
  ret = tm.strftime("%a, #{tm.mday} %b %Y %X ")
  gmt = Time.at(tm.to_i)
  gmt.gmtime
  offset = tm.to_i - Time.local(*gmt.to_a[0,6].reverse).to_i
  ret + sprintf('%+.2d%.2d', *(offset / 60).divmod(60))
end

$datestr = time2str(Time.now)
$ecvsuser = ENV['LOGNAME']
$pgrp = Process.getpgrp()

#
# parse arguments
#

puts "Invoking loginfo.rb...."

def usage()
  puts <<-EOF
Usage: #{MYNAME} CVSROOT USER 'CVS-LOG-STRING' MAIL_ADDRESSES
	[-d HELO_DOMAIN] [-s SMTP_SERVER] [-p SUBJECT_PREFIX]
	[-S SENDER_ADDRESS] [-R REPLY_TO_ADDRESS] [-x X_HEADER_PREFIX]
	[-w CVSWEB_URL] [-C PATH_TO_CVS] [-J]

-d	specify the domain to use in the SMTP session and in the mail header
	(default: FQDN of the host)
-s	specify the SMTP server to mail via
	(default: "localhost")
-S	specify the sender address for the mail
	(default: USER + "@" + HELO_DOMAIN)
-R	specify the reply-to address for the mail
	(default: none)
-p	specify the prefix for the mail subject (which will be surrounded
	by `[' and `]')
	(default: "cvs")
-x	specify the prefix for the CVS informative headers
	(default: "X-")
-w	specify the URL of the CVSweb with two @\'s, one for a path, and
	the other for a query (e.g. "'http://a.b/cvsweb.cgi@?cvsroot=xyz&@'")
	(default: none - no CVSweb links will be added)
-C	specify the full path to cvs
	(default: "/usr/bin/cvs")
-J	enable Japanese support (send mail in the JIS encoding)
	(default: disabled)
  EOF
end

if ARGV.size < 4
  usage()
  exit 1	# No way!
end

$cvsroot, $cvsuser, $cvsarg, $mailaddr = ARGV.slice!(0, 4)

$USAGE = 'usage'
parseArgs(0, nil, 'J',
	  'd:' + Socket::gethostbyname(Socket::gethostname)[0],
	  's:localhost',
	  'S:',
	  'R:',
	  'p:cvs',
	  'x:X-',
	  'w:',
	  'C:/usr/bin/cvs')

$helo_domain = $OPT_d
$smtp_server = $OPT_s
$subject_prefix = $OPT_p.strip
$x_header_prefix = $OPT_x.strip
$cvsweb_url = $OPT_w
$cvs_cmd = $OPT_C
$japanese_support = $OPT_J
$reply_to_address = $OPT_R

if $OPT_S
  $sender_address = $OPT_S
else
  $sender_address = "#{$ecvsuser}@#{$helo_domain}"
end

$from_address = sprintf('%s (%s)', $sender_address, $ecvsuser)

# Temporary control files
$commitinfosavefile	= sprintf("/tmp/commitinfo.%s.%d", $cvsuser, $pgrp)
$loginfosavefile	= sprintf("/tmp/loginfo.%s.%d", $cvsuser, $pgrp)
$changelogfile		= sprintf("/tmp/loginfo.changelog.%s.%d", $cvsuser, $pgrp)
$addlogfile		= sprintf("/tmp/loginfo.addlog.%s.%d", $cvsuser, $pgrp)
$modlogfile		= sprintf("/tmp/loginfo.modlog.%s.%d", $cvsuser, $pgrp)
$removelogfile		= sprintf("/tmp/loginfo.removelog.%s.%d", $cvsuser, $pgrp)
$modulesfile		= sprintf("/tmp/loginfo.modules.%s.%d", $cvsuser, $pgrp)

def cleanup_tmpfiles
  for f in [
      $commitinfosavefile,
      $loginfosavefile,
      $changelogfile,
      $addlogfile,
      $modlogfile,
      $removelogfile,
      $modulesfile ]
    File.unlink(f) rescue true
  end
end

def read_file(fn)
  File.open(fn, "r") do |f|
    f.read
  end
end

def append_line(fn, s)
  File.open(fn, "a+") do |f|
    f.puts s
  end
end

class String
  def indent(n)
    self.gsub(/^/, ' ' * n)
  end
end

def build_header(subject)
  subject = "[#{$subject_prefix}] #{subject}"

  header = <<EOF
Return-Path: #{$sender_address}
From: #{$from_address}
Date: #{$datestr}
Subject: #{subject}
To: #{$mailaddr}
EOF

  if $reply_to_address
    header << <<EOF
Reply-To: #{$reply_to_address}
EOF
  end

  header << <<EOF
Sender: #{$sender_address}
#{$x_header_prefix}CVS-User: #{$cvsuser}
#{$x_header_prefix}CVS-Root: #{$cvsroot}
#{$x_header_prefix}CVS-Module: #{$modulenames.join(', ')}
#{$x_header_prefix}CVS-Branch: #{$branch}
EOF

  header
end

def build_bodyheader
  '%-10s  %s' % [$cvsuser, $datestr] + "\n\n"
end

def build_mail(subject, body)
  build_header(subject) + "\n" + body
end

def send_mail(mail)
  require "net/smtp"

  begin
    sm = Net::SMTPSession.new($smtp_server, 25)
    sm.start($helo_domain)

    if $japanese_support
      require "kconv"
      mail = Kconv.tojis(mail)
    end

    sm.sendmail(mail, "#{$sender_address}", $mailaddr.split(/,/))
  rescue
    puts "ERROR: cannot send email using MTA on #{$smtp_server}"
  end
end

def previous_rev(rev)
  /^(.*\.)(\d+)$/ =~ rev or return nil

  main = $1
  last = $2.to_i

  if last == 1 && rev.split('.').length & 1 == 0 	# a branch, EVILNESS
    main.sub(/\.(\d+)\.$/, '')
  else
    main + (last - 1).to_s
  end
end

def cvsweb_url(modulename, filename, query)
  i = 0

  $cvsweb_url.gsub(/@/) { |at|
    case i += 1
    when 1
      "/#{modulename}/#{filename}"
    when 2
      query
    else
      at
    end
  }
end


# Save the first argument in a file
# File name is formatted as : "loginfo.%s.%d"

append_line($loginfosavefile, $cvsarg)

commithash = {}
loghash = {}

$isimport = ($cvsarg =~ /Imported sources$/)

if !$isimport
  # compare commitinfo temp files and loginfo temp files.
  # If the two files are logically equal, we know this time is the last one.

  begin
    cfile = File.open($commitinfosavefile, "r")
    lfile = File.open($loginfosavefile, "r")
  rescue => e
    print e.message
    cleanup_tmpfiles
    exit 0
  end

  cfile.each_line { |i|
    i.chomp!
    tk = i.split(/ /)
    croot = tk.shift	# CVSROOT mod-path file file file...
    cmodpath = tk.shift.sub(/^#{Regexp.quote(croot)}\//, "")
    tk.each { |j|
      commithash["#{cmodpath}/#{j}"] = true
    }
  }
  lfile.each_line { |i|
    i.chomp!
    tk = i.split(/ /)
    lmodpath = tk.shift
    tk.each { |j|
      loghash["#{lmodpath}/#{j}"] = true
    }
  }


  # Use "cvs log" and "cvs status" and save output string
  print "loginfo.rb is writing changelog..."

  cvsargtk = $cvsarg.split(/ /)
  modulename = cvsargtk.shift

  cvsargtk.each { |f|
    rev = ""
    `#{$cvs_cmd} -Qn status #{f}`.each_line { |l|
      l.strip!
	    
      if /^Repository revision:\s+(\S+)/ =~ l
	rev = $1
	break
      end
    }
    found = false
    `#{$cvs_cmd} -Qn log #{f}`.each_line { |l|
      l.strip!
	    
      if found
	if /state:\s+(\S+);(?:\s+lines:\s+(\S+)\s+(\S+))?$/ =~ l
	  state, plus, minus = $1, $2, $3

	  rev_prev = previous_rev(rev)

	  if state == 'dead'
	    append_line($changelogfile, 
			sprintf("%-11s %-9s  %s/%s",
				rev, '-REMOVED-', modulename, f))

	    if $cvsweb_url
	      append_line($changelogfile, 
			  cvsweb_url(modulename, f,
				     "rev=#{rev_prev}").indent(2))
	    end
	  elsif plus.nil?
	    append_line($changelogfile, 
			sprintf("%-11s %-9s  %s/%s",
				rev, '-ADDED-', modulename, f))

	    if $cvsweb_url
	      append_line($changelogfile, 
			  cvsweb_url(modulename, f,
				     "rev=#{rev}").indent(2))
	    end
	  else
	    append_line($changelogfile, 
			sprintf("%-11s %-4s %-4s  %s/%s",
				rev, plus, minus, modulename, f))

	    if $cvsweb_url
	      append_line($changelogfile, 
			  cvsweb_url(modulename, f,
				     "r1=#{rev_prev}&r2=#{rev}").indent(2))
	    end
	  end
	end

	break
      elsif /^revision\s(.+)$/ =~ l && $1 == rev
	found = true
      end
    }
  }

  puts "done"
end

# parse STDIN and sort out messages
print "loginfo.rb is parsing log message..." 

readmode = :init
files_begin = false
modulename = ""
logtext = ""
statustext = ""
$branch = "HEAD"

STDIN.each_line do |l|
  case l
  when /^Update of (.*)/
    modulename = $1.strip.sub(/^#{Regexp.quote($cvsroot)}\//, "")
    append_line($modulesfile, modulename)
    next
  when /^Modified Files:/
    readmode = :modify
    files_begin = true
    next
  when /^Added Files:/
    readmode = :add
    files_begin = true
    next
  when /^Removed Files:/
    readmode = :remove
    files_begin = true
    next
  when /^Log Message:/
    readmode = :log
    next
  when /^Status:/
    readmode = :status
    next
  when /^\s+Tag:\s+(\S+)$/
    $branch = $1
    next
  when nil
    break
  end

  case readmode
  when :modify, :add, :remove
    file = if readmode == :modify then
	     $modlogfile
	   elsif readmode == :add then
	     $addlogfile
	   else
	     $removelogfile
	   end

    if files_begin
      append_line(file, "#{modulename}:")
      files_begin = false
    end

    s = l.strip
    append_line(file, s.indent(2))
  when :log
    logtext << l
  when :status
    statustext << l
  end
end

puts "done"

# We need more modules...
print "loginfo.rb is testing modules..."
commithash.each_key { |k|
  if loghash[k].nil?
    puts "log info for `#{k}' is not ready" 
    exit 0
  end
}
puts "done"


#
# we can send a mail.
#

print "loginfo.rb is composing a mail..."

$modulenames = (read_file($modulesfile).chomp.split("\n") rescue Array.new)

# Use the first valuable line as the subject of the mail.
subject = "#{$modulenames.join(', ')}: "
logtext.each_line { |i|
  i.strip!
  if i != ""
    subject << i
    break
  end
}

branchinfo = if $branch == 'HEAD'
	       ""
	     else
	       "        (Branch: #{$branch})"
	     end

logtext.chomp!

body = build_bodyheader

if $isimport
  body <<
    ("Module:\n" +
     $modulenames.join("\n").indent(2) + "\n" +
     "Log:\n" +
     logtext.chomp.indent(2) + "\n" +
     "\n" +
     "Imported files:#{branchinfo}\n" +
     statustext.indent(2)).indent(2)
else
  body <<
    (("Modified files:#{branchinfo}\n" +
     read_file($modlogfile).indent(2) rescue "") +
     ("Added files:#{branchinfo}\n" +
      read_file($addlogfile).indent(2) rescue "") +
     ("Removed files:#{branchinfo}\n" +
      read_file($removelogfile).indent(2) rescue "") +
     "Log:\n" +
     logtext.chomp.indent(2) + "\n" +
     "\n" +
     ("Revision    Changes    Path\n" +
      read_file($changelogfile).chomp rescue "")).indent(2)
end

mail = build_mail(subject, body)

puts "done"

# detect _nomail_
if logtext =~ /_nomail_/
  puts "loginfo.rb is not posting email."
  puts "The composed mail is as follows:"
  puts mail
else
  print "loginfo.rb is posting email to #{$mailaddr} ..."
  send_mail(mail)
  puts "done"
end

# remove all temp files

print "loginfo.rb is deleting tmp files..."
cleanup_tmpfiles

puts "done"

exit 0
