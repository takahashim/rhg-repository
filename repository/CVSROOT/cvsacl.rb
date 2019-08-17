#
# CVS ACL checker module
#
# $devId: cvsacl.rb,v 1.3 2001/02/22 21:18:01 knu Exp $
# $Id: cvsacl.rb,v 1.3 2001/02/22 21:20:02 knu Exp $
#

class Group
  @@group_table = {}

  def Group::add(gid, obj)
    @@group_table[gid] = if obj.is_a?(Group) then obj else Group.new(obj) end
  end

  def Group::group(gid)
    if @@group_table.key? gid
      @@group_table[gid]
    else
      nil
    end
  end

  def initialize(list)
    @members = []
    @all = false

    return if list == nil

    list.each do |e|
      if e =~ /^@(.*)/
	gid = $1

	g = Group.group(gid)

	if g == nil
	  puts "No such group defined: '#{gid}'"
	  next
	end

	if g.all?
	  all!
	  break
	end

	@members |= g.members
      else
	@members |= [e]
      end
    end
  end

  def all?
    @all
  end

  def all!
    @all = true
    @member = nil
    self
  end

  def member?(u)
    @all || @members.member?(u)
  end

  def members
    @members
  end

  def to_str
    if all?
      '<everyone>'
    else
      @members.join ' '
    end
  end

  alias to_s to_str

  # Register a special group named 'all'
  add('all', new(nil).all!)
end

def check_acl(aclfile, hostname, user, modulename)
  debug = false

  File.open(aclfile) do |f|
    f.each_line do |line|
      line.strip!
      case line
      when /^#/, /^$/
	next
      else
	fields = line.split(':')
	command, arg1, arg2 = *fields
	
	command = command.intern

	case command
	when :debug
	  case arg1
	  when '0', 'off'
	    puts "DEBUG: debug mode: off" if debug
	    debug = false
	  else
	    debug = arg1
	    puts "DEBUG: debug mode: " + debug
	    puts "DEBUG: repo host: " + hostname
	    puts "DEBUG: user: " + user
	    puts "DEBUG: module: " + modulename
	  end
	when :host
	  h = hostname.downcase

	  repohosts = arg1.split(',')

	  unless repohosts.find { |r| r.downcase == h }
	    puts "ERROR: You are committing on `#{hostname}'!  Please specify CVSROOT properly and commit on `#{repohosts[0]}'."
	    return false
	  end
	when :group
	  g = Group.add(arg1, arg2.split(','))
	  puts "DEBUG: group added: <#{arg1}> = " + g if debug
	when :deny, :grant
	  g = Group.new(arg1.split(','))

	  if g.member? user
	    re = Regexp.new("^/?(?:#{arg2})(?:/|$)", 'i')

	    if re =~ modulename
	      puts "DEBUG: #{command.to_s}: " + g if debug

	      if command == :deny
		puts "ERROR: Access denied."
		return false
	      end

	      return true
	    end
	  end
	end
      end
    end
  end

  puts "DEBUG: grant" if debug
  true		# Grant by default
end

if $0 == __FILE__
  p check_acl(*ARGV)
end
