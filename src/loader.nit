# This file is part of NIT ( http://www.nitlanguage.org ).
#
# Copyright 2012 Jean Privat <jean@pryen.org>
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

# Loading of Nit source files
module loader

import modelbuilder_base
import ini

redef class ToolContext
	# Option --path
	var opt_path = new OptionArray("Set include path for loaders (may be used more than once)", "-I", "--path")

	# Option --only-metamodel
	var opt_only_metamodel = new OptionBool("Stop after meta-model processing", "--only-metamodel")

	# Option --only-parse
	var opt_only_parse = new OptionBool("Only proceed to parse step of loaders", "--only-parse")

	redef init
	do
		super
		option_context.add_option(opt_path, opt_only_parse, opt_only_metamodel)
	end
end

redef class ModelBuilder
	redef init
	do
		super

		# Setup the paths value
		paths.append(toolcontext.opt_path.value)

		var path_env = "NIT_PATH".environ
		if not path_env.is_empty then
			paths.append(path_env.split_with(':'))
		end

		var nit_dir = toolcontext.nit_dir
		var libname = nit_dir/"lib"
		if libname.file_exists then paths.add(libname)
		libname = nit_dir/"contrib"
		if libname.file_exists then paths.add(libname)
	end

	# Load a bunch of modules.
	# `modules` can contains filenames or module names.
	# Imported modules are automatically loaded and modelized.
	# The result is the corresponding model elements.
	# Errors and warnings are printed with the toolcontext.
	#
	# Note: class and property model elements are not analysed.
	fun parse(modules: Sequence[String]): Array[MModule]
	do
		var time0 = get_time
		# Parse and recursively load
		self.toolcontext.info("*** PARSE ***", 1)
		var mmodules = new ArraySet[MModule]
		for a in modules do
			var nmodule = self.load_module(a)
			if nmodule == null then continue # Skip error
			# Load imported module
			build_module_importation(nmodule)
			var mmodule = nmodule.mmodule
			if mmodule == null then continue # skip error
			mmodules.add mmodule
		end
		var time1 = get_time
		self.toolcontext.info("*** END PARSE: {time1-time0} ***", 2)

		self.toolcontext.check_errors

		if toolcontext.opt_only_parse.value then
			self.toolcontext.info("*** ONLY PARSE...", 1)
			exit(0)
		end

		return mmodules.to_a
	end

	# Load recursively all modules of the group `mgroup`.
	# See `parse` for details.
	fun parse_group(mgroup: MGroup): Array[MModule]
	do
		var res = new Array[MModule]
		scan_group(mgroup)
		for mg in mgroup.in_nesting.smallers do
			for mp in mg.module_paths do
				var nmodule = self.load_module(mp.filepath)
				if nmodule == null then continue # Skip error
				# Load imported module
				build_module_importation(nmodule)
				var mmodule = nmodule.mmodule
				if mmodule == null then continue # Skip error
				res.add mmodule
			end
		end
		return res
	end

	# Load a bunch of modules and groups.
	#
	# Each name can be:
	#
	# * a path to a module, a group or a directory of packages.
	# * a short name of a module or a group that are looked in the `paths` (-I)
	#
	# Then, for each entry, if it is:
	#
	# * a module, then is it parser and returned.
	# * a group then recursively all its modules are parsed.
	# * a directory of packages then all the modules of all packages are parsed.
	# * else an error is displayed.
	#
	# See `parse` for details.
	fun parse_full(names: Sequence[String]): Array[MModule]
	do
		var time0 = get_time
		# Parse and recursively load
		self.toolcontext.info("*** PARSE ***", 1)
		var mmodules = new ArraySet[MModule]
		for a in names do
			# Case of a group
			var mgroup = self.get_mgroup(a)
			if mgroup != null then
				mmodules.add_all parse_group(mgroup)
				continue
			end

			# Case of a directory that is not a group
			var stat = a.to_path.stat
			if stat != null and stat.is_dir then
				self.toolcontext.info("look in directory {a}", 2)
				var fs = a.files
				# Try each entry as a group or a module
				for f in fs do
					var af = a/f
					mgroup = get_mgroup(af)
					if mgroup != null then
						mmodules.add_all parse_group(mgroup)
						continue
					end
					var mp = identify_file(af)
					if mp != null then
						var nmodule = self.load_module(af)
						if nmodule == null then continue # Skip error
						build_module_importation(nmodule)
						var mmodule = nmodule.mmodule
						if mmodule == null then continue # Skip error
						mmodules.add mmodule
					else
						self.toolcontext.info("ignore file {af}", 2)
					end
				end
				continue
			end

			var nmodule = self.load_module(a)
			if nmodule == null then continue # Skip error
			# Load imported module
			build_module_importation(nmodule)
			var mmodule = nmodule.mmodule
			if mmodule == null then continue # Skip error
			mmodules.add mmodule
		end
		var time1 = get_time
		self.toolcontext.info("*** END PARSE: {time1-time0} ***", 2)

		self.toolcontext.check_errors

		if toolcontext.opt_only_parse.value then
			self.toolcontext.info("*** ONLY PARSE...", 1)
			exit(0)
		end

		return mmodules.to_a
	end

	# The list of directories to search for top level modules
	# The list is initially set with:
	#
	#   * the toolcontext --path option
	#   * the NIT_PATH environment variable
	#   * `toolcontext.nit_dir`
	# Path can be added (or removed) by the client
	var paths = new Array[String]

	# Like (and used by) `get_mmodule_by_name` but just return the ModulePath
	fun search_mmodule_by_name(anode: nullable ANode, mgroup: nullable MGroup, name: String): nullable ModulePath
	do
		# First, look in groups
		var c = mgroup
		if c != null then
			var r = c.mpackage.root
			assert r != null
			scan_group(r)
			var res = r.mmodule_paths_by_name(name)
			if res.not_empty then return res.first
		end

		# Look at some known directories
		var lookpaths = self.paths

		# Look in the directory of the group package also (even if not explicitly in the path)
		if mgroup != null then
			# path of the root group
			var dirname = mgroup.mpackage.root.filepath
			if dirname != null then
				dirname = dirname.join_path("..").simplify_path
				if not lookpaths.has(dirname) and dirname.file_exists then
					lookpaths = lookpaths.to_a
					lookpaths.add(dirname)
				end
			end
		end

		var candidate = search_module_in_paths(anode.hot_location, name, lookpaths)

		if candidate == null then
			if mgroup != null then
				error(anode, "Error: cannot find module `{name}` from `{mgroup.name}`. Tried: {lookpaths.join(", ")}.")
			else
				error(anode, "Error: cannot find module `{name}`. Tried: {lookpaths.join(", ")}.")
			end
			return null
		end
		return candidate
	end

	# Get a module by its short name; if required, the module is loaded, parsed and its hierarchies computed.
	# If `mgroup` is set, then the module search starts from it up to the top level (see `paths`);
	# if `mgroup` is null then the module is searched in the top level only.
	# If no module exists or there is a name conflict, then an error on `anode` is displayed and null is returned.
	fun get_mmodule_by_name(anode: nullable ANode, mgroup: nullable MGroup, name: String): nullable MModule
	do
		var path = search_mmodule_by_name(anode, mgroup, name)
		if path == null then return null # Forward error
		return load_module_path(path)
	end

	# Load and process importation of a given ModulePath.
	#
	# Basically chains `load_module` and `build_module_importation`.
	fun load_module_path(path: ModulePath): nullable MModule
	do
		var res = self.load_module(path.filepath)
		if res == null then return null # Forward error
		# Load imported module
		build_module_importation(res)
		return res.mmodule
	end

	# Search a module `name` from path `lookpaths`.
	# If found, the path of the file is returned
	private fun search_module_in_paths(location: nullable Location, name: String, lookpaths: Collection[String]): nullable ModulePath
	do
		var res = new ArraySet[ModulePath]
		for dirname in lookpaths do
			# Try a single module file
			var mp = identify_file((dirname/"{name}.nit").simplify_path)
			if mp != null then res.add mp
			# Try the default module of a group
			var g = get_mgroup((dirname/name).simplify_path)
			if g != null then
				scan_group(g)
				res.add_all g.mmodule_paths_by_name(name)
			end
		end
		if res.is_empty then return null
		if res.length > 1 then
			toolcontext.error(location, "Error: conflicting module files for `{name}`: `{res.join(",")}`")
		end
		return res.first
	end

	# Search groups named `name` from paths `lookpaths`.
	private fun search_group_in_paths(name: String, lookpaths: Collection[String]): ArraySet[MGroup]
	do
		var res = new ArraySet[MGroup]
		for dirname in lookpaths do
			# try a single group directory
			var mg = get_mgroup(dirname/name)
			if mg != null then
				res.add mg
			end
		end
		return res
	end

	# Cache for `identify_file` by realpath
	private var identified_files_by_path = new HashMap[String, nullable ModulePath]

	# All the currently identified modules.
	# See `identify_file`.
	var identified_files = new Array[ModulePath]

	# Identify a source file and load the associated package and groups if required.
	#
	# This method does what the user expects when giving an argument to a Nit tool.
	#
	# * If `path` is an existing Nit source file (with the `.nit` extension),
	#   then the associated ModulePath is returned
	# * If `path` is a directory (with a `/`),
	#   then the ModulePath of its default module is returned (if any)
	# * If `path` is a simple identifier (eg. `digraph`),
	#   then the main module of the package `digraph` is searched in `paths` and returned.
	#
	# Silently return `null` if `path` does not exists or cannot be identified.
	fun identify_file(path: String): nullable ModulePath
	do
		# special case for not a nit file
		if not path.has_suffix(".nit") then
			# search dirless files in known -I paths
			if not path.chars.has('/') then
				var res = search_module_in_paths(null, path, self.paths)
				if res != null then return res
			end

			# Found nothing? maybe it is a group...
			var candidate = null
			if path.file_exists then
				var mgroup = get_mgroup(path)
				if mgroup != null then
					var owner_path = mgroup.filepath.join_path(mgroup.name + ".nit")
					if owner_path.file_exists then candidate = owner_path
				end
			end

			if candidate == null then
				return null
			end
			path = candidate
		end

		# Does the file exists?
		if not path.file_exists then
			return null
		end

		# Fast track, the path is already known
		var pn = path.basename(".nit")
		var rp = module_absolute_path(path)
		if identified_files_by_path.has_key(rp) then return identified_files_by_path[rp]

		# Search for a group
		var mgrouppath = path.join_path("..").simplify_path
		var mgroup = get_mgroup(mgrouppath)

		if mgroup == null then
			# singleton package
			var mpackage = new MPackage(pn, model)
			mgroup = new MGroup(pn, mpackage, null) # same name for the root group
			mgroup.filepath = path
			mpackage.root = mgroup
			toolcontext.info("found singleton package `{pn}` at {path}", 2)

			# Attach homonymous `ini` file to the package
			var inipath = path.dirname / "{pn}.ini"
			if inipath.file_exists then
				var ini = new ConfigTree(inipath)
				mpackage.ini = ini
			end
		end

		var res = new ModulePath(pn, path, mgroup)
		mgroup.module_paths.add(res)

		identified_files_by_path[rp] = res
		identified_files.add(res)
		return res
	end

	# Groups by path
	private var mgroups = new HashMap[String, nullable MGroup]

	# Return the mgroup associated to a directory path.
	# If the directory is not a group null is returned.
	#
	# Note: `paths` is also used to look for mgroups
	fun get_mgroup(dirpath: String): nullable MGroup
	do
		if not dirpath.file_exists then do
			for p in paths do
				var try = p / dirpath
				if try.file_exists then
					dirpath = try
					break label
				end
			end
			return null
		end label

		var rdp = module_absolute_path(dirpath)
		if mgroups.has_key(rdp) then
			return mgroups[rdp]
		end

		# Filter out non-directories
		var stat = dirpath.file_stat
		if stat == null or not stat.is_dir then
			mgroups[rdp] = null
			return null
		end

		# By default, the name of the package or group is the base_name of the directory
		var pn = rdp.basename(".nit")

		# Check `package.ini` that indicate a package
		var ini = null
		var parent = null
		var inipath = dirpath / "package.ini"
		if inipath.file_exists then
			ini = new ConfigTree(inipath)
		end

		if ini == null then
			# No ini, multiple course of action

			# The root of the directory hierarchy in the file system.
			if rdp == "/" then
				mgroups[rdp] = null
				return null
			end

			# Special stopper `packages.ini`
			if (dirpath/"packages.ini").file_exists then
				# dirpath cannot be a package since it is a package directory
				mgroups[rdp] = null
				return null
			end

			# check the parent directory (if it does not contain the stopper file)
			var parentpath = dirpath.join_path("..").simplify_path
			var stopper = parentpath / "packages.ini"
			if not stopper.file_exists then
				# Recursively get the parent group
				parent = get_mgroup(parentpath)
				if parent == null then
					# Parent is not a group, thus we are not a group either
					mgroups[rdp] = null
					return null
				end
			end
		end

		var mgroup
		if parent == null then
			# no parent, thus new package
			if ini != null then pn = ini["package.name"] or else pn
			var mpackage = new MPackage(pn, model)
			mgroup = new MGroup(pn, mpackage, null) # same name for the root group
			mpackage.root = mgroup
			toolcontext.info("found package `{mpackage}` at {dirpath}", 2)
			mpackage.ini = ini
		else
			mgroup = new MGroup(pn, parent.mpackage, parent)
			toolcontext.info("found sub group `{mgroup.full_name}` at {dirpath}", 2)
		end

		# search documentation
		# in src first so the documentation of the package code can be distinct for the documentation of the package usage
		var readme = dirpath.join_path("README.md")
		if not readme.file_exists then readme = dirpath.join_path("README")
		if readme.file_exists then
			var mdoc = load_markdown(readme)
			mgroup.mdoc = mdoc
			mdoc.original_mentity = mgroup
		end

		mgroup.filepath = dirpath
		mgroups[rdp] = mgroup
		return mgroup
	end

	# Load a markdown file as a documentation object
	fun load_markdown(filepath: String): MDoc
	do
		var s = new FileReader.open(filepath)
		var lines = new Array[String]
		var line_starts = new Array[Int]
		var len = 1
		while not s.eof do
			var line = s.read_line
			lines.add(line)
			line_starts.add(len)
			len += line.length + 1
		end
		s.close
		var source = new SourceFile.from_string(filepath, lines.join("\n"))
		source.line_starts.add_all line_starts
		var mdoc = new MDoc(new Location(source, 1, lines.length, 0, 0))
		mdoc.content.add_all(lines)
		return mdoc
	end

	# Force the identification of all ModulePath of the group and sub-groups in the file system.
	#
	# When a group is scanned, its sub-groups hierarchy is filled (see `MGroup::in_nesting`)
	# and the potential modules (and nested modules) are identified (see `MGroup::module_paths`).
	#
	# Basically, this recursively call `get_mgroup` and `identify_file` on each directory entry.
	#
	# No-op if the group was already scanned (see `MGroup::scanned`).
	fun scan_group(mgroup: MGroup) do
		if mgroup.scanned then return
		mgroup.scanned = true
		var p = mgroup.filepath
		# a virtual group has nothing to scan
		if p == null then return
		for f in p.files do
			var fp = p/f
			var g = get_mgroup(fp)
			# Recursively scan for groups of the same package
			if g != null and g.mpackage == mgroup.mpackage then
				scan_group(g)
			end
			identify_file(fp)
		end
	end

	# Transform relative paths (starting with '../') into absolute paths
	private fun module_absolute_path(path: String): String do
		return path.realpath
	end

	# Try to load a module AST using a path.
	# Display an error if there is a problem (IO / lexer / parser) and return null
	fun load_module_ast(filename: String): nullable AModule
	do
		if not filename.has_suffix(".nit") then
			self.toolcontext.error(null, "Error: file `{filename}` is not a valid nit module.")
			return null
		end
		if not filename.file_exists then
			self.toolcontext.error(null, "Error: file `{filename}` not found.")
			return null
		end

		self.toolcontext.info("load module {filename}", 2)

		# Load the file
		var file = new FileReader.open(filename)
		var lexer = new Lexer(new SourceFile(filename, file))
		var parser = new Parser(lexer)
		var tree = parser.parse
		file.close

		# Handle lexer and parser error
		var nmodule = tree.n_base
		if nmodule == null then
			var neof = tree.n_eof
			assert neof isa AError
			error(neof, neof.message)
			return null
		end

		return nmodule
	end

	# Remove Nit source files from a list of arguments.
	#
	# Items of `args` that can be loaded as a nit file will be removed from `args` and returned.
	fun filter_nit_source(args: Array[String]): Array[String]
	do
		var keep = new Array[String]
		var res = new Array[String]
		for a in args do
			var l = identify_file(a)
			if l == null then
				keep.add a
			else
				res.add a
			end
		end
		args.clear
		args.add_all(keep)
		return res
	end

	# Try to load a module using a path.
	# Display an error if there is a problem (IO / lexer / parser) and return null.
	# Note: usually, you do not need this method, use `get_mmodule_by_name` instead.
	#
	# The MModule is created however, the importation is not performed,
	# therefore you should call `build_module_importation`.
	fun load_module(filename: String): nullable AModule
	do
		# Look for the module
		var file = identify_file(filename)
		if file == null then
			if filename.file_exists then
				toolcontext.error(null, "Error: `{filename}` is not a Nit source file.")
			else
				toolcontext.error(null, "Error: cannot find module `{filename}`.")
			end
			return null
		end

		# Already known and loaded? then return it
		var mmodule = file.mmodule
		if mmodule != null then
			return mmodule2nmodule[mmodule]
		end

		# Load it manually
		var nmodule = load_module_ast(file.filepath)
		if nmodule == null then return null # forward error

		# build the mmodule and load imported modules
		mmodule = build_a_mmodule(file.mgroup, file.name, nmodule)

		if mmodule == null then return null # forward error

		# Update the file information
		file.mmodule = mmodule

		return nmodule
	end

	# Injection of a new module without source.
	# Used by the interpreter.
	fun load_rt_module(parent: nullable MModule, nmodule: AModule, mod_name: String): nullable AModule
	do
		# Create the module

		var mgroup = null
		if parent != null then mgroup = parent.mgroup
		var mmodule = new MModule(model, mgroup, mod_name, nmodule.location)
		nmodule.mmodule = mmodule
		nmodules.add(nmodule)
		self.mmodule2nmodule[mmodule] = nmodule

		if parent!= null then
			var imported_modules = new Array[MModule]
			imported_modules.add(parent)
			mmodule.set_visibility_for(parent, intrude_visibility)
			mmodule.set_imported_mmodules(imported_modules)
		else
			build_module_importation(nmodule)
		end

		return nmodule
	end

	# Visit the AST and create the `MModule` object
	private fun build_a_mmodule(mgroup: nullable MGroup, mod_name: String, nmodule: AModule): nullable MModule
	do
		# Check the module name
		var decl = nmodule.n_moduledecl
		if decl != null then
			var decl_name = decl.n_name.n_id.text
			if decl_name != mod_name then
				error(decl.n_name, "Error: module name mismatch; declared {decl_name} file named {mod_name}.")
			end
		end

		# Check for conflicting module names in the package
		if mgroup != null then
			var others = model.get_mmodules_by_name(mod_name)
			if others != null then for other in others do
				if other.mgroup!= null and other.mgroup.mpackage == mgroup.mpackage then
					var node: ANode
					if decl == null then node = nmodule else node = decl.n_name
					error(node, "Error: a module named `{other.full_name}` already exists at {other.location}.")
					break
				end
			end
		end

		# Create the module
		var mmodule = new MModule(model, mgroup, mod_name, nmodule.location)
		nmodule.mmodule = mmodule
		nmodules.add(nmodule)
		self.mmodule2nmodule[mmodule] = nmodule

		var source = nmodule.location.file
		if source != null then
			assert source.mmodule == null
			source.mmodule = mmodule
		end

		if decl != null then
			# Extract documentation
			var ndoc = decl.n_doc
			if ndoc != null then
				var mdoc = ndoc.to_mdoc
				mmodule.mdoc = mdoc
				mdoc.original_mentity = mmodule
			else
				advice(decl, "missing-doc", "Documentation warning: Undocumented module `{mmodule}`")
			end
			# Is the module a test suite?
			mmodule.is_test_suite = not decl.get_annotations("test_suite").is_empty
		end

		return mmodule
	end

	# Resolve the module identification for a given `AModuleName`.
	#
	# This method handles qualified names as used in `AModuleName`.
	fun seach_module_by_amodule_name(n_name: AModuleName, mgroup: nullable MGroup): nullable ModulePath
	do
		var mod_name = n_name.n_id.text

		# If a quad is given, we ignore the starting group (go from path)
		if n_name.n_quad != null then mgroup = null

		# If name not qualified, just search the name
		if n_name.n_path.is_empty then
			# Fast search if no n_path
			return search_mmodule_by_name(n_name, mgroup, mod_name)
		end

		# If qualified and in a group
		if mgroup != null then
			# First search in the package
			var r = mgroup.mpackage.root
			assert r != null
			scan_group(r)
			# Get all modules with the final name
			var res = r.mmodule_paths_by_name(mod_name)
			# Filter out the name that does not match the qualifiers
			res = [for x in res do if match_amodulename(n_name, x) then x]
			if res.not_empty then
				if res.length > 1 then
					error(n_name, "Error: conflicting module files for `{mod_name}`: `{res.join(",")}`")
				end
				return res.first
			end
		end

		# If no module yet, then assume that the first element of the path
		# Is to be searched in the path.
		var root_name = n_name.n_path.first.text
		var roots = search_group_in_paths(root_name, paths)
		if roots.is_empty then
			error(n_name, "Error: cannot find `{root_name}`. Tried: {paths.join(", ")}.")
			return null
		end

		var res = new ArraySet[ModulePath]
		for r in roots do
			# Then, for each root, collect modules that matches the qualifiers
			scan_group(r)
			var root_res = r.mmodule_paths_by_name(mod_name)
			for x in root_res do if match_amodulename(n_name, x) then res.add x
		end
		if res.not_empty then
			if res.length > 1 then
				error(n_name, "Error: conflicting module files for `{mod_name}`: `{res.join(",")}`")
			end
			return res.first
		end
		# If still nothing, just call a basic search that will fail and will produce an error message
		error(n_name, "Error: cannot find module `{mod_name}` from `{root_name}`. Tried: {paths.join(", ")}.")
		return null
	end

	# Is elements of `n_name` correspond to the group nesting of `m`?
	#
	# Basically it check that `bar::foo` matches `bar/foo.nit` and `bar/baz/foo.nit`
	# but not `baz/foo.nit` nor `foo/bar.nit`
	#
	# Is used by `seach_module_by_amodule_name` to validate qualified names.
	private fun match_amodulename(n_name: AModuleName, m: ModulePath): Bool
	do
		var g: nullable MGroup = m.mgroup
		for grp in n_name.n_path.reverse_iterator do
			while g != null and grp.text != g.name do
				g = g.parent
			end
		end
		return g != null
	end

	# Analyze the module importation and fill the module_importation_hierarchy
	#
	# Unless you used `load_module`, the importation is already done and this method does a no-op.
	fun build_module_importation(nmodule: AModule)
	do
		if nmodule.is_importation_done then return
		nmodule.is_importation_done = true
		var mmodule = nmodule.mmodule.as(not null)
		var stdimport = true
		var imported_modules = new Array[MModule]
		for aimport in nmodule.n_imports do
			# Do not imports conditional
			var atconditionals = aimport.get_annotations("conditional")
			if atconditionals.not_empty then continue

			stdimport = false
			if not aimport isa AStdImport then
				continue
			end

			# Load the imported module
			var suppath = seach_module_by_amodule_name(aimport.n_name, mmodule.mgroup)
			if suppath == null then
				nmodule.mmodule = null # invalidate the module
				continue # Skip error
			end
			var sup = load_module_path(suppath)
			if sup == null then
				nmodule.mmodule = null # invalidate the module
				continue # Skip error
			end

			aimport.mmodule = sup
			imported_modules.add(sup)
			var mvisibility = aimport.n_visibility.mvisibility
			if mvisibility == protected_visibility then
				error(aimport.n_visibility, "Error: only properties can be protected.")
				nmodule.mmodule = null # invalidate the module
				return
			end
			if sup == mmodule then
				error(aimport.n_name, "Error: dependency loop in module {mmodule}.")
				nmodule.mmodule = null # invalidate the module
			end
			if sup.in_importation < mmodule then
				error(aimport.n_name, "Error: dependency loop between modules {mmodule} and {sup}.")
				nmodule.mmodule = null # invalidate the module
				return
			end
			mmodule.set_visibility_for(sup, mvisibility)
		end
		if stdimport then
			var mod_name = "core"
			var sup = self.get_mmodule_by_name(nmodule, null, mod_name)
			if sup == null then
				nmodule.mmodule = null # invalidate the module
			else # Skip error
				imported_modules.add(sup)
				mmodule.set_visibility_for(sup, public_visibility)
			end
		end

		# Declare conditional importation
		for aimport in nmodule.n_imports do
			if not aimport isa AStdImport then continue
			var atconditionals = aimport.get_annotations("conditional")
			if atconditionals.is_empty then continue

			var suppath = seach_module_by_amodule_name(aimport.n_name, mmodule.mgroup)
			if suppath == null then continue # skip error

			for atconditional in atconditionals do
				var nargs = atconditional.n_args
				if nargs.is_empty then
					error(atconditional, "Syntax Error: `conditional` expects module identifiers as arguments.")
					continue
				end

				# The rule
				var rule = new Array[Object]

				# First element is the goal, thus
				rule.add suppath

				# Second element is the first condition, that is to be a client of the current module
				rule.add mmodule

				# Other condition are to be also a client of each modules indicated as arguments of the annotation
				for narg in nargs do
					var id = narg.as_id
					if id == null then
						error(narg, "Syntax Error: `conditional` expects module identifier as arguments.")
						continue
					end

					var mp = search_mmodule_by_name(narg, mmodule.mgroup, id)
					if mp == null then continue

					rule.add mp
				end

				conditional_importations.add rule
			end
		end

		mmodule.set_imported_mmodules(imported_modules)

		apply_conditional_importations(mmodule)

		self.toolcontext.info("{mmodule} imports {mmodule.in_importation.direct_greaters.join(", ")}", 3)

		# Force `core` to be public if imported
		for sup in mmodule.in_importation.greaters do
			if sup.name == "core" then
				mmodule.set_visibility_for(sup, public_visibility)
			end
		end

		# TODO: Correctly check for useless importation
		# It is even doable?
		var directs = mmodule.in_importation.direct_greaters
		for nim in nmodule.n_imports do
			if not nim isa AStdImport then continue
			var im = nim.mmodule
			if im == null then continue
			if directs.has(im) then continue
			# This generates so much noise that it is simpler to just comment it
			#warning(nim, "Warning: possible useless importation of {im}")
		end
	end

	# Global list of conditional importation rules.
	#
	# Each rule is a "Horn clause"-like sequence of modules.
	# It means that the first module is the module to automatically import.
	# The remaining modules are the conditions of the rule.
	#
	# Each module is either represented by a MModule (if the module is already loaded)
	# or by a ModulePath (if the module is not yet loaded).
	#
	# Rules are declared by `build_module_importation` and are applied by `apply_conditional_importations`
	# (and `build_module_importation` that calls it).
	#
	# TODO (when the loader will be rewritten): use a better representation and move up rules in the model.
	private var conditional_importations = new Array[SequenceRead[Object]]

	# Extends the current importations according to imported rules about conditional importation
	fun apply_conditional_importations(mmodule: MModule)
	do
		# Because a conditional importation may cause additional conditional importation, use a fixed point
		# The rules are checked naively because we assume that it does not worth to be optimized
		var check_conditional_importations = true
		while check_conditional_importations do
			check_conditional_importations = false

			for ci in conditional_importations do
				# Check conditions
				for i in [1..ci.length[ do
					var rule_element = ci[i]
					# An element of a rule is either a MModule or a ModulePath
					# We need the mmodule to resonate on the importation
					var m
					if rule_element isa MModule then
						m = rule_element
					else if rule_element isa ModulePath then
						m = rule_element.mmodule
						# Is loaded?
						if m == null then continue label
					else
						abort
					end
					# Is imported?
					if not mmodule.in_importation.greaters.has(m) then continue label
				end
				# Still here? It means that all conditions modules are loaded and imported

				# Identify the module to automatically import
				var suppath = ci.first.as(ModulePath)
				var sup = load_module_path(suppath)
				if sup == null then continue

				# Do nothing if already imported
				if mmodule.in_importation.greaters.has(sup) then continue label

				# Import it
				self.toolcontext.info("{mmodule} conditionally imports {sup}", 3)
				# TODO visibility rules (currently always public)
				mmodule.set_visibility_for(sup, public_visibility)
				# TODO linearization rules (currently added at the end in the order of the rules)
				mmodule.set_imported_mmodules([sup])

				# Prepare to reapply the rules
				check_conditional_importations = true
			end label
		end
	end

	# All the loaded modules
	var nmodules = new Array[AModule]

	# Register the nmodule associated to each mmodule
	#
	# Public clients need to use `mmodule2node` to access stuff.
	private var mmodule2nmodule = new HashMap[MModule, AModule]

	# Retrieve the associated AST node of a mmodule.
	# This method is used to associate model entity with syntactic entities.
	#
	# If the module is not associated with a node, returns null.
	fun mmodule2node(mmodule: MModule): nullable AModule
	do
		return mmodule2nmodule.get_or_null(mmodule)
	end
end

# File-system location of a module (file) that is identified but not always loaded.
class ModulePath
	# The name of the module
	# (it's the basename of the filepath)
	var name: String

	# The human path of the module
	var filepath: String

	# The group (and the package) of the possible module
	var mgroup: MGroup

	# The loaded module (if any)
	var mmodule: nullable MModule = null

	redef fun to_s do return filepath
end

redef class MPackage
	# The associated `.ini` file, if any
	#
	# The `ini` file is given as is and might contain invalid or missing information.
	#
	# Some packages, like stand-alone packages or virtual packages have no `ini` file associated.
	var ini: nullable ConfigTree = null
end

redef class MGroup
	# Modules paths associated with the group
	var module_paths = new Array[ModulePath]

	# Is the group interesting for a final user?
	#
	# Groups are mandatory in the model but for simple packages they are not
	# always interesting.
	#
	# A interesting group has, at least, one of the following true:
	#
	# * it has 2 modules or more
	# * it has a subgroup
	# * it has a documentation
	fun is_interesting: Bool
	do
		return module_paths.length > 1 or
			mmodules.length > 1 or
			not in_nesting.direct_smallers.is_empty or
			mdoc != null or
			(mmodules.length == 1 and default_mmodule == null)
	end

	# Are files and directories in self scanned?
	#
	# See `ModelBuilder::scan_group`.
	var scanned = false

	# Return the modules in self and subgroups named `name`.
	#
	# If `self` is not scanned (see `ModelBuilder::scan_group`) the
	# results might be partial.
	fun mmodule_paths_by_name(name: String): Array[ModulePath]
	do
		var res = new Array[ModulePath]
		for g in in_nesting.smallers do
			for mp in g.module_paths do
				if mp.name == name then
					res.add mp
				end
			end
		end
		return res
	end
end

redef class SourceFile
	# Associated mmodule, once created
	var mmodule: nullable MModule = null
end

redef class AStdImport
	# The imported module once determined
	var mmodule: nullable MModule = null
end

redef class AModule
	# The associated MModule once build by a `ModelBuilder`
	var mmodule: nullable MModule
	# Flag that indicate if the importation is already completed
	var is_importation_done: Bool = false
end
