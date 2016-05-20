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
import testing_suite
import markdown
import html

# Extractor, Executor and Reporter for the tests in a module
class NitUnitExecutor
	super HTMLDecorator

	#
	var suite: TestSuite

	# Toolcontext used to parse Nit code blocks.
	fun toolcontext: ToolContext do return suite.toolcontext

	# The prefix of the generated Nit source-file
	var prefix: String

	# The module to import, if any
	var mmodule: nullable MModule

	# All blocks of code from a same `ADoc`
	var blocks = new Array[Buffer]

	# All failures from a same `ADoc`
	var failures = new Array[String]

	# Markdown processor used to parse markdown comments and extract code.
	var mdproc = new MarkdownProcessor

	init do
		mdproc.emitter.decorator = new NitunitDecorator(self)
	end

	# The associated documentation object
	var mdoc: nullable MDoc = null

	# used to generate distinct names
	var cpt = 0

	# The entry point for a new `ndoc` node
	# Fill `docunits` with new discovered unit of tests.
	#
	# `tc` (testcase) is the pre-filled XML node
	fun extract(mdoc: MDoc)
	do
		blocks.clear
		failures.clear

		self.mdoc = mdoc

		# Populate `blocks` from the markdown decorator
		mdproc.process(mdoc.content.join("\n"))

		toolcontext.check_errors

		if not failures.is_empty then
			for msg in failures do
				var du = new_du(mdoc, "") 
				du.error = msg
				toolcontext.modelbuilder.unit_entities += 1
				toolcontext.modelbuilder.failed_entities += 1
			end
		end

		if blocks.is_empty then return
		for block in blocks do
			var du = new_du(mdoc, block) 
			docunits.add du
		end
	end

	fun new_du(mdoc: MDoc, block: Text): DocUnit
	do
		var number = 0
		if docunits.not_empty and docunits.last.mdoc == mdoc then number = docunits.last.number + 1

		var du = new DocUnit(suite, mdoc.original_mentity.as(not null), mdoc, block.write_to_string, number)
		suite.add_test du
		return du
	end

	# All extracted docunits
	var docunits = new Array[DocUnit]

	# Execute all the docunits
	fun run_tests
	do
		var simple_du = new Array[DocUnit]
		for du in docunits do
			var ast = toolcontext.parse_something(du.block)
			if ast isa AExpr then
				simple_du.add du
			else
				test_single_docunit(du)
			end
		end

		test_simple_docunits(simple_du)
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
			f.write("# docunits: {du.mentity.full_name} #{du.number}\n")
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
			# Fall-back to individual modes:
			for du in dus do
				test_single_docunit(du)
			end
			return
		end

		i = 0
		for du in dus do
			toolcontext.modelbuilder.unit_entities += 1
			i += 1
			toolcontext.info("Execute doc-unit {du.mentity.full_name} in {file} {i}", 1)
			var res2 = toolcontext.safe_exec("{file.to_program_name}.bin {i} >'{file}.out1' 2>&1 </dev/null")
			du.was_exec = true

			var msg = "{file}.out1".to_path.read_all

			if res2 != 0 then
				du.error = msg
				toolcontext.warning(du.mdoc.location, "error", "ERROR: {du.mentity.full_name} (in {file}): Runtime error\n{msg}")
				toolcontext.modelbuilder.failed_entities += 1
			end
			toolcontext.check_errors
		end
	end

	# Executes a single doc-unit in its own program.
	# Used for docunits larger than a single block of code (with modules, classes, functions etc.)
	fun test_single_docunit(du: DocUnit)
	do
		toolcontext.modelbuilder.unit_entities += 1

		cpt += 1
		var file = "{prefix}-{cpt}.nit"

		toolcontext.info("Execute doc-unit {du.mentity.full_name} in {file}", 1)

		var f
		f = create_unitfile(file)
		f.write(du.block)
		f.close

		if toolcontext.opt_noact.value then return

		var res = compile_unitfile(file)
		var res2 = 0
		if res == 0 then
			res2 = toolcontext.safe_exec("{file.to_program_name}.bin >'{file}.out1' 2>&1 </dev/null")
		end

		var msg = "{file}.out1".to_path.read_all

		if res != 0 then
			du.error = msg
			toolcontext.warning(du.mdoc.location, "failure", "FAILURE: {du.full_name} (in {file}):\n{msg}")
			toolcontext.modelbuilder.failed_entities += 1
		else if res2 != 0 then
			du.was_exec = true
			du.error = msg
			toolcontext.warning(du.mdoc.location, "error", "ERROR: {du.full_name} (in {file}):\n{msg}")
			toolcontext.modelbuilder.failed_entities += 1
		end
		toolcontext.check_errors
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
		var cmd = "{nitc} --ignore-visibility --no-color '{file}' {opts.join(" ")} >'{file}.out1' 2>&1 </dev/null -o '{file}.bin'"
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

			executor.toolcontext.warning(location, "invalid-block", "{message} To suppress this message, enclose the block with a fence tagged `nitish` or `raw` (see `man nitdoc`).")

			executor.failures.add("{location}: {message}")
			return
		end

		# Create a first block
		# Or create a new block for modules that are more than a main part
		if executor.blocks.is_empty or ast isa AModule then
			executor.blocks.add(new Buffer)
		end

		# Add it to the file
		executor.blocks.last.append code
	end
end

# A unit-test to run
class DocUnit
	super TestCase

	# The doc that contains self
	var mdoc: MDoc

	# The text of the code to execute
	var block: String

	# The number of the doc unit in the mdoc
	var number: Int

	redef fun xml_classname: String
	do
		var mentity = self.mentity

		if mentity isa MPropDef then mentity = mentity.mclassdef

		if mentity isa MModule then
			return mentity.full_name + ".<Module>"
		else if mentity isa MClassDef then
			return mentity.mmodule.full_name + "." + mentity.name
		else
			abort
		end
	end

	redef fun xml_name: String
	do
		var mentity = self.mentity

		var res = ""
		if mentity isa MModule then
			res = "<module>"
		else if mentity isa MClassDef then
			res = "<class>"
		else if mentity isa MPropDef then
			res = mentity.name
		else
			abort
		end
		if number > 0 then
			res += "+{number}"
		end
		return res
	end

	redef fun to_xml
	do
		var res = super
		res.open("system-out").append block
		return res
	end
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

	fun extract_units(nue: NitUnitExecutor, mentity: MEntity)
	do
		total_entities += 1
		var mdoc = mentity.mdoc
		if mdoc == null then return
		doc_entities += 1
		if mdoc.original_mentity != mentity then return

		nue.extract(mdoc)
		print "Got {mentity}"
	end

	# Extracts and executes all the docunits in the `mmodule`
	# Returns a JUnit-compatible `<testsuite>` XML element that contains the results of the executions.
	fun test_markdown(mmodule: MModule): HTMLTag
	do
		var suite = new TestSuite(mmodule, toolcontext)

		toolcontext.info("nitunit: doc-unit {mmodule}", 2)

		# Usually, only the original module must be imported in the unit test.
		var o = mmodule
		var g = o.mgroup
		if g != null and g.mpackage.name == "core" then
			var nmodule = mmodule2node(mmodule)
			# except for a unit test in a module of `core`
			# in this case, the whole `core` must be imported
			if nmodule != null then o = get_mmodule_by_name(nmodule, g, g.mpackage.name).as(not null)
		end

		var prefix = toolcontext.test_dir
		prefix = prefix.join_path(mmodule.to_s)
		var d2m = new NitUnitExecutor(suite, prefix, o)

		extract_units(d2m, mmodule)
		for mclassdef in mmodule.mclassdefs do
			extract_units(d2m, mclassdef)
			for mpropdef in mclassdef.mpropdefs do
				extract_units(d2m, mpropdef)
			end
		end

		d2m.run_tests

		return suite.to_xml
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
		var suite = new TestSuite(null, toolcontext)
		var d2m = new NitUnitExecutor(suite, prefix, o)

		var tc

		total_entities += 1
		var mdoc = mgroup.mdoc
		if mdoc == null then return ts

		doc_entities += 1
		tc = new HTMLTag("testcase")
		# NOTE: jenkins expects a '.' in the classname attr
		tc.attr("classname", "nitunit." + mgroup.full_name)
		tc.attr("name", "<group>")

		d2m.run_tests

		return ts
	end

	# Test a document object unrelated to a Nit entity
	fun test_mdoc(mdoc: MDoc): HTMLTag
	do
		var ts = new HTMLTag("testsuite")
		var file = mdoc.location.to_s

		toolcontext.info("nitunit: doc-unit file {file}", 2)

		ts.attr("package", file)

		var prefix = toolcontext.test_dir / "file"
		var suite = new TestSuite(null, toolcontext)
		var d2m = new NitUnitExecutor(suite, prefix, null)

		var tc

		total_entities += 1
		doc_entities += 1

		tc = new HTMLTag("testcase")
		# NOTE: jenkins expects a '.' in the classname attr
		tc.attr("classname", "nitunit.<file>")
		tc.attr("name", file)

		d2m.run_tests

		return ts
	end
end
