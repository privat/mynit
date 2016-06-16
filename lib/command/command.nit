
intrude import core::exec
import standard

# A configured command ready to be executed as a sub-process.
class Command
	var cmd: String

	var args = new Array[String]

	var process: nullable Process = null

	var status: nullable Int = null

	fun run: Command
	do
		var p = process
		if p != null then return self

		print "#RUN"

		var i = cached_stdin
		var o = cached_stdout
		
		if i == null then
			if o == null then
				p = new Process(cmd, args...)
			else
				p = new ProcessReader(cmd, args...)
				o.stream = p.stream_in
			end
		else
			if o == null then
				p = new ProcessWriter(cmd, args...)
			else
				p = new ProcessDuplex(cmd, args...)
				o.stream = p.stream_in
			end
			i.stream = p.stream_out
		end
		process = p
		return self
	end

	fun wait: Command
	do
		var p = process
		if p == null then return self
		print "#WAIT"
		var i = cached_stdin
		if i != null then i.close
		var o = cached_stdout
		if o != null then o.close
		p.wait
		status = p.status
		return self
	end

	# Return a redirection for stdin
	#
	# This method must be called before the `run`.
	# When called, a input pipe to the command will be returned.
	fun stdin: Writer
	do
		assert process == null

		var res = cached_stdin
		if res != null then return res
		res = new CmdIn(self)
		cached_stdin = res
		return res
	end

	private var cached_stdin: nullable CmdIn = null

	fun stdout: Reader
	do
		assert process == null

		var res = cached_stdout
		if res != null then return res
		res = new CmdOut(self)
		cached_stdout = res
		return res
	end

	private var cached_stdout: nullable CmdOut = null
end

private class CmdStream
	super Stream

	var command: Command
end

private class CmdIn
	super CmdStream
	super Writer

	var stream: nullable FileWriter = null

	fun run_process: nullable FileWriter
	do
		var p = stream
		if p != null then return p
		print "# irun"
		command.run
		return stream
	end

	redef fun close
	do
		var p = run_process
		if p != null then p.close
	end

	redef fun write(s)
	do
		var p = run_process
		if p != null then p.write(s)
	end
end

private class CmdOut
	super CmdStream
	super Reader

	var stream: nullable FileReader = null

	fun run_process: nullable FileReader
	do
		var p = stream
		if p != null then return p
		print "# orun"
		command.run
		return stream
	end

	redef fun close
	do
		var p = run_process
		if p != null then p.close
	end

	redef fun eof
	do
		var p = run_process
		if p != null then return p.eof
		return true
	end

	redef fun read_bytes(i)
	do
		var p = run_process
		if p != null then return p.read_bytes(i)
		return new Bytes.empty
	end

	redef fun read_byte
	do
		var p = run_process
		if p != null then return p.read_byte
		return null 
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
print "echo".to_command(["hello", "world"]).run.wait.status or else "?"

print "\n# simple input"
var cmd = "wc".to_command
"Hello World\nFoo".write_to cmd.stdin
print cmd.wait.status or else "?"

print "\n# simple output"
cmd = "echo".to_command(["hello", "world"])
print cmd.stdout.read_all.to_upper
print cmd.wait.status or else "?"

print "\n$ simple duplex"
cmd = "tr".to_command(["a-z", "A-Z"])
var i = cmd.stdin
var o = cmd.stdout
"Hello World".write_to i
i.close
print o.read_all
print cmd.wait.status or else "?"

