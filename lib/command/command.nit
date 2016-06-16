# Simple and high-level API to execute commands as sub-processes.
module command

intrude import core::exec
import standard

# A configured command ready to be executed as a sub-process.
class Command
	# The program to execute.
	var prog: String

	# The arguments of the program.
	var args = new Array[String]

	# Was `start` already called?
	fun is_started: Bool do return process != null

	# The process object
	#
	# While you can access it, it is better to rely on the `command` API
	# since `Process` may change in a near future.
	var process: nullable Process = null

	# The return code of the command.
	#
	# Is `null` until wait is called.
	var status: nullable Int = null

	# Starts the command.
	#
	# If the command was already started, this is a no-op.
	#
	# ENSURE `is_started`
	fun start: Command
	do
		var p = process
		if p != null then return self

		var i = cached_stdin
		var o = cached_stdout
		
		if i == null then
			if o == null then
				p = new Process(prog, args...)
			else
				p = new ProcessReader(prog, args...)
				o.stream = p.stream_in
			end
		else
			if o == null then
				p = new ProcessWriter(prog, args...)
			else
				p = new ProcessDuplex(prog, args...)
				o.stream = p.stream_in
			end
			i.stream = p.stream_out
		end
		process = p
		return self
	end

	fun finish
	do
		wait
	end

	# Await the completion of the command.
	#
	# See `man wait`.
	fun wait: Int
	do
		var s = status
		if s != null then return s

		start
		var p = process
		assert p != null

		var i = cached_stdin
		if i != null then i.close
		var o = cached_stdout
		if o != null then o.close

		p.wait

		s = p.status
		status = s
		return s
	end

	# Return the redirection for the standard input of the command.
	#
	# By default, the standard input of the command is inherited from the current process.
	#
	# When this method is called, the standard input of the command will be replaced by a pipe.
	# After the first call, the same object will be returned.
	# 
	# Note that the pipe must be created before the command is started.
	# This is an hard requirement.
	#
	# Moreover, to avoid deadlock, the command must be started before anything is written.
	# Therefore, if needed, `start` will be implicitly called on the first write access.
	fun stdin: Writer
	do
		var res = cached_stdin
		if res != null then return res

		assert process == null
		res = new CmdWriter(self)
		cached_stdin = res
		return res
	end

	private var cached_stdin: nullable CmdWriter = null

	# Return the redirection for the standard output of the command.
	#
	# By default, the standard output of the command is inherited from the current process.
	#
	# When this method is called, the standard output of the command will be replaced by a pipe.
	# After the first call, the same object will be returned.
	# 
	# Note that the pipe must be created before the command is started.
	# This is an hard requirement.
	#
	# Moreover, to avoid deadlock, the command must be started before anything is read.
	# Therefore, if needed, `start` will be implicitly called on the first read access.
	fun stdout: Reader
	do
		var res = cached_stdout
		if res != null then return res

		assert process == null
		res = new CmdReader(self)
		cached_stdout = res
		return res
	end

	private var cached_stdout: nullable CmdReader = null
end

# Common class to handle redirection and lazy pipe creation
private abstract class CmdStream
	super Stream

	# The associated command
	var command: Command

	redef fun start do command.start

	redef fun finish do command.finish
end

# Handle stdin redirection
private class CmdWriter
	super CmdStream
	super Writer

	# The associated stream.
	#
	# Is null until the command is started.
	var stream: nullable FileWriter = null

	# Force the associated stream. Start the process if needed.
	fun run_process: FileWriter
	do
		var p = stream
		if p != null then return p
		command.start
		return stream.as(not null)
	end

	redef fun close
	do
		var p = run_process
		p.close
	end

	redef fun write(s)
	do
		var p = run_process
		p.write(s)
	end
end

# Handle stdout redirection
private class CmdReader
	super CmdStream
	super Reader

	# The associated stream.
	#
	# Is null until the command is started.
	var stream: nullable FileReader = null

	# Force the associated stream. Start the process if needed.
	fun run_process: FileReader
	do
		var p = stream
		if p != null then return p
		command.start
		return stream.as(not null)
	end

	redef fun close
	do
		var p = run_process
		p.close
	end

	redef fun eof
	do
		var p = run_process
		return p.eof
	end

	redef fun read_bytes(i)
	do
		var p = run_process
		return p.read_bytes(i)
	end

	redef fun read_byte
	do
		var p = run_process
		return p.read_byte
	end

	redef fun read_char
	do
		var p = run_process
		return p.read_char
	end
end

redef class String
	# Return `self` as a simple command.
	#
	# `self` must be a valid program and can be either a path to an executable
	# or a the name of an executable available in the PATH.
	fun to_command(args: nullable Array[String]): Command
	do
		var res = new Command(self)
		if args != null then res.args.add_all args
		return res
	end

	# Returns `self` as a shell command.
	#
	# See option `-c` of `man sh`.
	#
	# 
	fun to_shell_command(args: nullable Array[String]): Command
	do
		var sh_args = ["-c", self]
		if args != null then sh_args.add_all args
		return "/bin/sh".to_command(sh_args)
	end
end

print "# Simple echo"
print "echo".to_command(["hello", "world"]).wait

print "\n# simple input"
var cmd = "wc".to_command
"Hello World\nFoo".write_to cmd.stdin
print cmd.wait

print "\n# simple output"
cmd = "echo".to_command(["hello", "world"])
print cmd.stdout.read_all.to_upper
print cmd.wait

print "\n$ simple duplex"
cmd = "tr".to_command(["a-z", "A-Z"])
var i = cmd.stdin
var o = cmd.stdout
"Hello World".write_to i
i.close
print o.read_all
print cmd.wait

