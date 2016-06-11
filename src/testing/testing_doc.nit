# This file is part of NIT ( http://www.nitlanguage.org ).
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Testing from code comments.
module testing_doc

private import parser_util
import testing_base
import markdown
import html
import realtime

# Extractor, Executor and Reporter for the tests in a module
class NitUnitExecutor
	super HTMLDecorator

	# Toolcontext used to parse Nit code blocks.
	var toolcontext: ToolContext

	# The prefix of the generated Nit source-file
	var prefix: String

	# The module to import, if any
	var mmodule: nullable MModule

	# The XML node associated to the module
	var testsuite: HTMLTag

	# The name of the suite
	var name: String

	# Markdown processor used to parse markdown comments and extract code.
	var mdproc = new MarkdownProcessor

	init do
		mdproc.emitter.decorator = new NitunitDecorator(self)
	end

	# The associated documentation object
	var mdoc: nullable MDoc = null

	# used to generate distinct names
	var cpt = 0

	# The last docunit extracted from a mdoc.
	#
	# Is used because a new code-block might just be added to it.
	var last_docunit: nullable DocUnit = null

	var xml_classname: String is noautoinit

	var xml_name: String is noautoinit

	# The entry point for a new `ndoc` node
	# Fill `docunits` with new discovered unit of tests.
	fun extract(mdoc: MDoc, xml_classname, xml_name: String)
	do
		last_docunit = null
		self.xml_classname = xml_classname
		self.xml_name = xml_name

		self.mdoc = mdoc

		# Populate `blocks` from the markdown decorator
		mdproc.process(mdoc.content.join("\n"))
	end

	# All extracted docunits
	var docunits = new Array[DocUnit]

	fun show_status
	do
		toolcontext.show_unit_status(name, docunits)
	end

	fun mark_done(du: DocUnit)
	do
		du.is_done = true
		toolcontext.clear_progress_bar
		toolcontext.show_unit(du)
		show_status
	end

	# Execute all the docunits
	fun run_tests
	do
		if docunits.is_empty then
			return
		end

		# Try to group each nitunit into a single source file to fasten the compilation
		var simple_du = new Array[DocUnit]
		show_status
		for du in docunits do
			# Skip existing errors
			if du.error != null then
				continue
			end

			var ast = toolcontext.parse_something(du.block)
			if ast isa AExpr then
				simple_du.add du
			end
		end
		test_simple_docunits(simple_du)

		# Now test them in order
		for du in docunits do
			if du.error != null then
				# Nothing to execute. Conclude
			else if du.test_file != null then
				# Already compiled. Execute it.
				execute_simple_docunit(du)
			else
				# Need to try to compile it, then execute it
				test_single_docunit(du)
			end
			mark_done(du)
		end

		# Final status
		show_status
		print ""

		for du in docunits do
			testsuite.add du.to_xml
		end
	end

	# Executes multiples doc-units in a shared program.
	# Used for docunits simple block of code (without modules, classes, functions etc.)
	#
	# In case of compilation error, the method fallbacks to `test_single_docunit` to
	# * locate exactly the compilation problem in the problematic docunit.
	# * permit the execution of the other docunits that may be correct.
	fun test_simple_docunits(dus: Array[DocUnit])
	do
		if dus.is_empty then return

		var file = "{prefix}-0.nit"

		var dir = file.dirname
		if dir != "" then dir.mkdir
		var f
		f = create_unitfile(file)
		var i = 0
		for du in dus do

			i += 1
			f.write("fun run_{i} do\n")
			f.write("# {du.full_name}\n")
			f.write(du.block)
			f.write("end\n")
		end
		f.write("var a = args.first.to_i\n")
		for j in [1..i] do
			f.write("if a == {j} then run_{j}\n")
		end
		f.close

		if toolcontext.opt_noact.value then return

		var res = compile_unitfile(file)

		if res != 0 then
			# Compilation error.
			# They will be executed independently
			return
		end

		# Compilation was a success.
		# Store what need to be executed for each one.
		i = 0
		for du in dus do
			i += 1
			du.test_file = file
			du.test_arg = i
		end
	end

	# Execute a docunit compiled by `test_single_docunit`
	fun execute_simple_docunit(du: DocUnit)
	do
		var file = du.test_file.as(not null)
		var i = du.test_arg.as(not null)
		toolcontext.info("Execute doc-unit {du.full_name} in {file} {i}", 1)
		var clock = new Clock
		var res2 = toolcontext.safe_exec("{file.to_program_name}.bin {i} >'{file}.out1' 2>&1 </dev/null")
		du.real_time = clock.total
		du.was_exec = true

		var content = "{file}.out1".to_path.read_all
		du.raw_output = content

		if res2 != 0 then
			du.error = "Runtime error in {file} with argument {i}"
			toolcontext.modelbuilder.failed_entities += 1
		end
	end

	# Executes a single doc-unit in its own program.
	# Used for docunits larger than a single block of code (with modules, classes, functions etc.)
	fun test_single_docunit(du: DocUnit)
	do
		cpt += 1
		var file = "{prefix}-{cpt}.nit"

		toolcontext.info("Execute doc-unit {du.full_name} in {file}", 1)

		var f
		f = create_unitfile(file)
		f.write(du.block)
		f.close

		if toolcontext.opt_noact.value then return

		var res = compile_unitfile(file)
		var res2 = 0
		if res == 0 then
			var clock = new Clock
			res2 = toolcontext.safe_exec("{file.to_program_name}.bin >'{file}.out1' 2>&1 </dev/null")
			du.real_time = clock.total
			du.was_exec = true
		end

		var content = "{file}.out1".to_path.read_all
		du.raw_output = content

		if res != 0 then
			du.error = "Compilation error in {file}"
			toolcontext.modelbuilder.failed_entities += 1
		else if res2 != 0 then
			du.error = "Runtime error in {file}"
			toolcontext.modelbuilder.failed_entities += 1
		end
	end

	# Create and fill the header of a unit file `file`.
	#
	# A unit file is a Nit source file generated from one
	# or more docunits that will be compiled and executed.
	#
	# The handled on the file is returned and must be completed and closed.
	#
	# `file` should be a valid filepath for a Nit source file.
	private fun create_unitfile(file: String): Writer
	do
		var dir = file.dirname
		if dir != "" then dir.mkdir
		var f
		f = new FileWriter.open(file)
		f.write("# GENERATED FILE\n")
		f.write("# Docunits extracted from comments\n")
		if mmodule != null then
			f.write("import {mmodule.name}\n")
		end
		f.write("\n")
		return f
	end

	# Compile an unit file and return the compiler return code
	#
	# Can terminate the program if the compiler is not found
	private fun compile_unitfile(file: String): Int
	do
		var nitc = toolcontext.find_nitc
		var opts = new Array[String]
		if mmodule != null then
			opts.add "-I {mmodule.filepath.dirname}"
		end
		var cmd = "{nitc} --ignore-visibility --no-color -q '{file}' {opts.join(" ")} >'{file}.out1' 2>&1 </dev/null -o '{file}.bin'"
		var res = toolcontext.safe_exec(cmd)
		return res
	end
end

private class NitunitDecorator
	super HTMLDecorator

	var executor: NitUnitExecutor

	redef fun add_code(v, block) do
		var code = block.raw_content
		var meta = block.meta or else "nit"
		# Do not try to test non-nit code.
		if meta != "nit" then return
		# Try to parse code blocks
		var ast = executor.toolcontext.parse_something(code)

		var mdoc = executor.mdoc
		assert mdoc != null

		# Skip pure comments
		if ast isa TComment then return

		# The location is computed according to the starts of the mdoc and the block
		# Note, the following assumes that all the comments of the mdoc are correctly aligned.
		var loc = block.block.location
		var line_offset = loc.line_start + mdoc.location.line_start - 2
		var column_offset = loc.column_start + mdoc.location.column_start
		# Hack to handle precise location in blocks
		# TODO remove when markdown is more reliable
		if block isa BlockFence then
			# Skip the starting fence
			line_offset += 1
		else
			# Account a standard 4 space indentation
			column_offset += 4
		end

		# We want executable code
		if not (ast isa AModule or ast isa ABlockExpr or ast isa AExpr) then
			var message
			var l = ast.location
			# Get real location of the node (or error)
			var location = new Location(mdoc.location.file,
				l.line_start + line_offset,
				l.line_end + line_offset,
				l.column_start + column_offset,
				l.column_end + column_offset)
			if ast isa AError then
				message = ast.message
			else
				message = "Error: Invalid Nit code."
			end

			var du = new_docunit
			du.block += code
			du.error_location = location
			du.error = message
			executor.toolcontext.modelbuilder.failed_entities += 1
			return
		end

		# Create a first block
		# Or create a new block for modules that are more than a main part
		var last_docunit = executor.last_docunit
		if last_docunit == null or ast isa AModule then
			last_docunit = new_docunit
			executor.last_docunit = last_docunit
		end

		# Add it to the file
		last_docunit.block += code

		# In order to retrieve precise positions,
		# the real position of each line of the raw_content is stored.
		# See `DocUnit::real_location`
		line_offset -= loc.line_start - 1
		for i in [loc.line_start..loc.line_end] do
			last_docunit.lines.add i + line_offset
			last_docunit.columns.add column_offset
		end
	end

	# Return and register a new empty docunit
	fun new_docunit: DocUnit
	do
		var mdoc = executor.mdoc
		assert mdoc != null

		var next_number = 1
		var name = executor.xml_name
		if executor.docunits.not_empty and executor.docunits.last.mdoc == mdoc then
			next_number = executor.docunits.last.number + 1
			name += "#" + next_number.to_s
		end

		var res = new DocUnit(mdoc, next_number, "", executor.xml_classname, name)
		executor.docunits.add res
		executor.toolcontext.modelbuilder.unit_entities += 1
		return res
	end
end

# A unit-test extracted from some documentation.
#
# A docunit is extracted from the code-blocks of mdocs.
# Each mdoc can contains more than one docunit, and a single docunit can be made of more that a single code-block.
class DocUnit
	super UnitTest

	# The doc that contains self
	var mdoc: MDoc

	# The numbering of self in mdoc (starting with 0)
	var number: Int

	# The generated Nit source file that contains the unit-test
	#
	# Note that a same generated file can be used for multiple tests.
	# See `test_arg` that is used to distinguish them
	var test_file: nullable String = null

	# The command-line argument to use when executing the test, if any.
	var test_arg: nullable Int = null

	redef fun full_name do
		var mentity = mdoc.original_mentity
		if mentity != null then
			var res = mentity.full_name
			if number > 1 then
				res += "#{number}"
			end
			return res
		else
			return xml_classname + "." + xml_name
		end
	end

	# The text of the code to execute.
	#
	# This is the verbatim content on one, or more, code-blocks from `mdoc`
	var block: String

	# For each line in `block`, the associated line in the mdoc
	#
	# Is used to give precise locations
	var lines = new Array[Int]

	# For each line in `block`, the associated column in the mdoc
	#
	# Is used to give precise locations
	var columns = new Array[Int]

	# The location of the whole docunit.
	#
	# If `self` is made of multiple code-blocks, then the location
	# starts at the first code-books and finish at the last one, thus includes anything between.
	redef var location is lazy do
		return new Location(mdoc.location.file, lines.first, lines.last+1, columns.first+1, 0)
	end

	# Compute the real location of a node on the `ast` based on `mdoc.location`
	#
	# The result is basically: ast_location + markdown location of the piece + mdoc.location
	#
	# The fun is that a single docunit can be made of various pieces of code blocks.
	fun real_location(ast_location: Location): Location
	do
		var mdoc = self.mdoc
		var res = new Location(mdoc.location.file, lines[ast_location.line_start-1],
			lines[ast_location.line_end-1],
			columns[ast_location.line_start-1] + ast_location.column_start,
			columns[ast_location.line_end-1] + ast_location.column_end)
		return res
	end

	redef fun to_xml
	do
		var res = super
		res.open("system-out").append(block)
		return res
	end

	redef var xml_classname
	redef var xml_name
end

redef class ModelBuilder
	# Total number analyzed `MEntity`
	var total_entities = 0

	# The number of `MEntity` that have some documentation
	var doc_entities = 0

	# The total number of executed docunits
	var unit_entities = 0

	# The number failed docunits
	var failed_entities = 0

	# Extracts and executes all the docunits in the `mmodule`
	# Returns a JUnit-compatible `<testsuite>` XML element that contains the results of the executions.
	fun test_markdown(mmodule: MModule): HTMLTag
	do
		var ts = new HTMLTag("testsuite")
		toolcontext.info("nitunit: doc-unit {mmodule}", 2)

		var nmodule = mmodule2node(mmodule)
		if nmodule == null then return ts

		# usualy, only the original module must be imported in the unit test.
		var o = mmodule
		var g = o.mgroup
		if g != null and g.mpackage.name == "core" then
			# except for a unit test in a module of `core`
			# in this case, the whole `core` must be imported
			o = get_mmodule_by_name(nmodule, g, g.mpackage.name).as(not null)
		end

		ts.attr("package", mmodule.full_name)

		var prefix = toolcontext.test_dir
		prefix = prefix.join_path(mmodule.to_s)
		var d2m = new NitUnitExecutor(toolcontext, prefix, o, ts, "Docunits of module {mmodule.full_name}")

		do
			total_entities += 1
			var nmoduledecl = nmodule.n_moduledecl
			if nmoduledecl == null then break label x
			var ndoc = nmoduledecl.n_doc
			if ndoc == null then break label x
			doc_entities += 1
			# NOTE: jenkins expects a '.' in the classname attr
			d2m.extract(ndoc.to_mdoc, "nitunit." + mmodule.full_name + ".<module>", "<module>")
		end label x
		for nclassdef in nmodule.n_classdefs do
			var mclassdef = nclassdef.mclassdef
			if mclassdef == null then continue
			if nclassdef isa AStdClassdef then
				total_entities += 1
				var ndoc = nclassdef.n_doc
				if ndoc != null then
					doc_entities += 1
					d2m.extract(ndoc.to_mdoc, "nitunit." + mclassdef.full_name.replace("$", "."), "<class>")
				end
			end
			for npropdef in nclassdef.n_propdefs do
				var mpropdef = npropdef.mpropdef
				if mpropdef == null then continue
				total_entities += 1
				var ndoc = npropdef.n_doc
				if ndoc != null then
					doc_entities += 1
					var a = mpropdef.full_name.split("$")
					d2m.extract(ndoc.to_mdoc, "nitunit." + a[0] + "." + a[1], a[2])
				end
			end
		end

		d2m.run_tests

		return ts
	end

	# Extracts and executes all the docunits in the readme of the `mgroup`
	# Returns a JUnit-compatible `<testsuite>` XML element that contains the results of the executions.
	fun test_group(mgroup: MGroup): HTMLTag
	do
		var ts = new HTMLTag("testsuite")
		toolcontext.info("nitunit: doc-unit group {mgroup}", 2)

		# usually, only the default module must be imported in the unit test.
		var o = mgroup.default_mmodule

		ts.attr("package", mgroup.full_name)

		var prefix = toolcontext.test_dir
		prefix = prefix.join_path(mgroup.to_s)
		var d2m = new NitUnitExecutor(toolcontext, prefix, o, ts, "Docunits of group {mgroup.full_name}")

		total_entities += 1
		var mdoc = mgroup.mdoc
		if mdoc == null then return ts

		doc_entities += 1
		# NOTE: jenkins expects a '.' in the classname attr
		d2m.extract(mdoc, "nitunit." + mgroup.mpackage.name + "." + mgroup.name + ".<group>", "<group>")

		d2m.run_tests

		return ts
	end

	# Test a document object unrelated to a Nit entity
	fun test_mdoc(mdoc: MDoc): HTMLTag
	do
		var ts = new HTMLTag("testsuite")
		var file = mdoc.location.file.filename

		toolcontext.info("nitunit: doc-unit file {file}", 2)

		ts.attr("package", file)

		var prefix = toolcontext.test_dir / "file"
		var d2m = new NitUnitExecutor(toolcontext, prefix, null, ts, "Docunits of file {file}")

		total_entities += 1
		doc_entities += 1

		# NOTE: jenkins expects a '.' in the classname attr
		d2m.extract(mdoc, "nitunit.<file>", file)
		d2m.run_tests

		return ts
	end
end
