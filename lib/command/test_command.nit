module test_command is test_suite

import test_suite
import command

class TestCommand
	super TestSuite

	fun test_simple_fg
	do
		"echo hello 1".to_shell_command.wait
		"echo $0 2".to_shell_command(["hello"]).wait
		"echo HELLO 3 | tr A-Z a-z".to_shell_command.wait
		"echo".to_command(["hello", "4"]).wait
		var c = new Command("echo")
		c.args.add_all(["hello", "4"])
		c.wait
	end

	fun test_stdout
	do
		var cmd = "echo hello 1; echo goodbye 2"
		assert cmd.to_shell_command.stdout.read_line == "hello 1"
		assert cmd.to_shell_command.stdout.read_all == "hello 1\ngoodbye 2\n"
		assert cmd.to_shell_command.stdout.each_line.to_a == ["hello 1", "goodbye 2"]
		assert cmd.to_shell_command.stdout.read_bytes(5) == "hello".to_bytes
		assert cmd.to_shell_command.stdout.read_all_bytes == "hello 1\ngoodbye 2\n".to_bytes
	end

	fun test_stdin
	do
		var cmd = "tr a-z A-Z"
		var c = cmd.to_shell_command

		"hello 1".write_to c.stdin
		"goodbye 2\n".write_to c.stdin

		assert c.wait == 0
	end

	fun test_stdout_with
	do
		var cmd = "echo hello 1; echo goodbye 2"
		var c = cmd.to_shell_command
		with s = c.stdout do
			assert s.read_line == "hello 1"
			assert s.read_line == "goodbye 2"
			assert c.status == null
		end
		assert c.status == 0
	end

	fun test_stdin_with
	do
		var cmd = "tr a-z A-Z"
		var c = cmd.to_shell_command
		with s = c.stdin do
			"hello 1".write_to s
			"goodbye 2\n".write_to s
			assert c.status == null
		end
		assert c.status == 0
	end

	fun test_duplex
	do
		var cmd = "tr a-z A-Z"
		var c = cmd.to_shell_command
		c.stdout

		"hello\n1".write_to c.stdin
		"goodbye 2".write_to c.stdin
		c.stdin.close

		assert c.stdout.read_line == "HELLO"
		assert c.stdout.read_all == "1GOODBYE 2"

		assert c.wait == 0
	end
end
