# Execution of commands as sub-process

## Quick Start

The `command` module is based on the `Command` class and the related services.
A `Command` encapsulates the configuration of a command and its execution as a sub-process.

How to execute a simple shell command?

~~~
import command

# Create, run and wait a sub-process
var status = "echo hello".to_shell_command.wait
# "hello" is printed
assert status == 0 # because `echo` returned 0
~~~

How to read the output of a simple command?

~~~
# Create the command
var uptime = "uptime".to_command
# Run it and read all its output
print uptime.stdout.read_all
# Close the stream and wait the end of the sub-process
uptime.wait
~~~

How to write to a simple shell command?

~~~
# Create the command
var tr = "tr a-z A-Z".to_shell_command
# Write some stuff
var txt = "some input"
txt.write_to tr.stdin
# Close the stream and wait the end of the sub-process
tr.wait
~~~

## Principles

The life-cycle of a command is decomposed into:

* the creation of the command, that is made of a program and arguments.
* the configuration of the redirections (pipes)
* the execution
* the wait and status retrieval

## Command Creation

There is 3 basic way to create a command.

* `String::to_command` that transform a program name/path to a command.

`self` can be a path, or a simple name that will be looked for in `PATH`.

~~~
var c1 = "dmesg".to_command
~~~

Arguments of the command can be given, if any.

~~~
var c2 = "/bin/ls".to_command(["-l", "-h"])
~~~

* `String::to_shell_command` that takes a `sh` compatible command. See option `-c` of `/bin/sh`.

~~~
var c3 = "echo hello".to_shell_command
~~~

As with `sh -c`, arguments can be provided.

~~~
var c4 = "echo \"$1\"".to_shell_command(["hello"])
~~~

## Command Configuration

When created, the command is not started automatically.
This allow you to configure further the command.

The main configuration is the creation of pipes to communicate with the command.

* `Command::stdin` will create a input pipe so you can send data.
* `Command::stdout` will create a output pipe so you can read data.

The pipes MUST be configured before the command is started

## Command Execution

The basic way to start the execution of the command is the `Command::start` method.
However, this method is implicitly called when:

* Something is written to `Command::stdout`
* Something is read from `Command::stdin`
* `Command::wait` is called

The fact that any access to `stdout` or `stdin` starts the process enable you to avoid complex configuration since

~~~
var c
c = "echo hello".to_shell_command
print c.stdout.read_line
c.wait
~~~

Is a simpler equivalent to

~~~
c = "echo hello".to_shell_command
var s = c.stdout # Configure the pipe BEFORE start
c.start
print s.read_line # Read from the pipe
c.wait
~~~

## Command Wait

When started, a command is run in background as a sub-process.

`Command::wait` is used to block the calling process until the sub-process is terminated.

If needed `wait` starts the execution so just calling `wait` is equivalent to a foreground execution.
