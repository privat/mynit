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

# Intra-procedural services based on types
module type_context

import modelize
import flow

# Knowledge and services to manipulate AST and types
#
# This class can be seen as a toolbox on a specific `MPropDef`
class TypeContext
	# The associated modelbuilder for output and AST queries
	var modelbuilder:  ModelBuilder

	# The module of the analysis
	# Used to correctly query the model
	var mmodule: MModule

	# The static type of the receiver
	# Mainly used for type tests and type resolutions
	var anchor: nullable MClassType = null

	# The analyzed mclassdef
	var mclassdef: nullable MClassDef = null

	# The analyzed property
	var mpropdef: nullable MPropDef

	# The local variable associated to self
	var selfvariable: nullable Variable is writable

	# Is `self` use restricted?
	# * no explicit `self`
	# * method called on the implicit self must be top-level
	# Currently only used for `new` factory since there is no valid receiver inside
	var is_toplevel_context = false

	init
	do
		var mpropdef = self.mpropdef

		if mpropdef != null then
			self.mpropdef = mpropdef
			var mclassdef = mpropdef.mclassdef
			self.mclassdef = mclassdef
			self.anchor = mclassdef.bound_mtype

			var mprop = mpropdef.mproperty
			if mprop isa MMethod and mprop.is_new then
				is_toplevel_context = true
			end
		end
	end

	fun anchor_to(mtype: MType): MType
	do
		var anchor = anchor
		if anchor == null then
			assert not mtype.need_anchor
			return mtype
		end
		return mtype.anchor_to(mmodule, anchor)
	end

	fun is_subtype(sub, sup: MType): Bool
	do
		return sub.is_subtype(mmodule, anchor, sup)
	end

	fun resolve_for(mtype, subtype: MType, for_self: Bool): MType
	do
		#print "resolve_for {mtype} sub={subtype} forself={for_self} mmodule={mmodule} anchor={anchor}"
		var res = mtype.resolve_for(subtype, anchor, mmodule, not for_self)
		return res
	end

	# Check that `sub` is a subtype of `sup`.
	# If `sub` is not a valid suptype, then display an error on `node` an return null.
	# If `sub` is a safe subtype of `sup` then return `sub`.
	# If `sub` is an unsafe subtype (ie an implicit cast is required), then return `sup`.
	#
	# The point of the return type is to determinate the usable type on an expression when `autocast` is true:
	# If the suptype is safe, then the return type is the one on the expression typed by `sub`.
	# Is the subtype is unsafe, then the return type is the one of an implicit cast on `sup`.
	fun check_subtype(node: ANode, sub, sup: MType, autocast: Bool): nullable MType
	do
		if self.is_subtype(sub, sup) then return sub
		if autocast and self.is_subtype(sub, self.anchor_to(sup)) then
			# FIXME workaround to the current unsafe typing policy. To remove once fixed virtual types exists.
			#node.debug("Unsafe typing: expected {sup}, got {sub}")
			return sup
		end
		if sup isa MBottomType then return null # Skip error
		if sub.need_anchor then
			var u = anchor_to(sub)
			self.modelbuilder.error(node, "Type Error: expected `{sup}`, got `{sub}: {u}`.")
		else
			self.modelbuilder.error(node, "Type Error: expected `{sup}`, got `{sub}`.")
		end
		return null
	end

	# Can `mtype` be null (up to the current knowledge)?
	fun can_be_null(mtype: MType): Bool
	do
		if mtype isa MNullableType or mtype isa MNullType then return true
		if mtype isa MFormalType then
			var x = anchor_to(mtype)
			if x isa MNullableType or x isa MNullType then return true
		end
		return false
	end

	# Check that `mtype` can be null (up to the current knowledge).
	#
	# If not then display a `useless-null-test` warning on node and return false.
	# Else return true.
	fun check_can_be_null(anode: ANode, mtype: MType): Bool
	do
		if mtype isa MNullType then
			modelbuilder.warning(anode, "useless-null-test", "Warning: expression is always `null`.")
			return true
		end
		if can_be_null(mtype) then return true

		if mtype isa MFormalType then
			var res = anchor_to(mtype)
			modelbuilder.warning(anode, "useless-null-test", "Warning: expression is not null, since it is a `{mtype}: {res}`.")
		else
			modelbuilder.warning(anode, "useless-null-test", "Warning: expression is not null, since it is a `{mtype}`.")
		end
		return false
	end

	fun try_get_mproperty_by_name2(anode: ANode, mtype: MType, name: String): nullable MProperty
	do
		return self.modelbuilder.try_get_mproperty_by_name2(anode, mmodule, mtype, name)
	end

	fun resolve_mtype(node: AType): nullable MType
	do
		return self.modelbuilder.resolve_mtype(mmodule, mclassdef, node)
	end

	fun try_get_mclass(node: ANode, name: String): nullable MClass
	do
		var mclass = modelbuilder.try_get_mclass_by_name(node, mmodule, name)
		return mclass
	end

	fun get_mclass(node: ANode, name: String): nullable MClass
	do
		var mclass = modelbuilder.get_mclass_by_name(node, mmodule, name)
		return mclass
	end

	fun type_bool(node: ANode): nullable MType
	do
		var mclass = self.get_mclass(node, "Bool")
		if mclass == null then return null
		return mclass.mclass_type
	end

	fun get_method(node: ANode, recvtype: MType, name: String, recv_is_self: Bool): nullable CallSite
	do
		var unsafe_type = self.anchor_to(recvtype)

		#debug("recv: {recvtype} (aka {unsafe_type})")
		if recvtype isa MNullType then
			var objclass = get_mclass(node, "Object")
			if objclass == null then return null # Forward error
			unsafe_type = objclass.mclass_type
		end

		var mproperty = self.try_get_mproperty_by_name2(node, unsafe_type, name)
		if name == "new" and mproperty == null then
			name = "init"
			mproperty = self.try_get_mproperty_by_name2(node, unsafe_type, name)
		end

		if mproperty == null then
			if recv_is_self then
				self.modelbuilder.error(node, "Error: method or variable `{name}` unknown in `{recvtype}`.")
			else if recvtype.need_anchor then
				self.modelbuilder.error(node, "Error: method `{name}` does not exists in `{recvtype}: {unsafe_type}`.")
			else
				self.modelbuilder.error(node, "Error: method `{name}` does not exists in `{recvtype}`.")
			end
			return null
		end

		assert mproperty isa MMethod

		# `null` only accepts some methods of object.
		if recvtype isa MNullType and not mproperty.is_null_safe then
			self.error(node, "Error: method `{name}` called on `null`.")
			return null
		else if unsafe_type isa MNullableType and not mproperty.is_null_safe then
			modelbuilder.advice(node, "call-on-nullable", "Warning: method call on a nullable receiver `{recvtype}`.")
		end

		if is_toplevel_context and recv_is_self and not mproperty.is_toplevel then
			error(node, "Error: `{name}` is not a top-level method, thus need a receiver.")
		end
		if not recv_is_self and mproperty.is_toplevel then
			error(node, "Error: cannot call `{name}`, a top-level method, with a receiver.")
		end

		if mproperty.visibility == protected_visibility and not recv_is_self and self.mmodule.visibility_for(mproperty.intro_mclassdef.mmodule) < intrude_visibility and not modelbuilder.toolcontext.opt_ignore_visibility.value then
			self.modelbuilder.error(node, "Error: method `{name}` is protected and can only accessed by `self`.")
			return null
		end

		var info = mproperty.deprecation
		if info != null and self.mpropdef.mproperty.deprecation == null then
			var mdoc = info.mdoc
			if mdoc != null then
				self.modelbuilder.warning(node, "deprecated-method", "Deprecation Warning: method `{name}` is deprecated: {mdoc.content.first}")
			else
				self.modelbuilder.warning(node, "deprecated-method", "Deprecation Warning: method `{name}` is deprecated.")
			end
		end

		var propdefs = mproperty.lookup_definitions(self.mmodule, unsafe_type)
		var mpropdef
		if propdefs.length == 0 then
			self.modelbuilder.error(node, "Type Error: no definition found for property `{name}` in `{unsafe_type}`.")
			return null
		else if propdefs.length == 1 then
			mpropdef = propdefs.first
		else
			self.modelbuilder.warning(node, "property-conflict", "Warning: conflicting property definitions for property `{name}` in `{unsafe_type}`: {propdefs.join(" ")}")
			mpropdef = mproperty.intro
		end


		var msignature = mpropdef.new_msignature or else mpropdef.msignature
		if msignature == null then return null # skip error
		msignature = resolve_for(msignature, recvtype, recv_is_self).as(MSignature)

		var erasure_cast = false
		var rettype = mpropdef.msignature.return_mtype
		if not recv_is_self and rettype != null then
			rettype = rettype.undecorate
			if rettype isa MParameterType then
				var erased_rettype = msignature.return_mtype
				assert erased_rettype != null
				#node.debug("Erasure cast: Really a {rettype} but unsafely a {erased_rettype}")
				erasure_cast = true
			end
		end

		var callsite = new CallSite(node.hot_location, recvtype, mmodule, anchor, recv_is_self, mproperty, mpropdef, msignature, erasure_cast)
		return callsite
	end

	fun try_get_method(node: ANode, recvtype: MType, name: String, recv_is_self: Bool): nullable CallSite
	do
		var unsafe_type = self.anchor_to(recvtype)
		var mproperty = self.try_get_mproperty_by_name2(node, unsafe_type, name)
		if mproperty == null then return null
		return get_method(node, recvtype, name, recv_is_self)
	end

	fun error(node: ANode, message: String)
	do
		self.modelbuilder.error(node, message)
	end

	fun merge_types(node: ANode, col: Array[nullable MType]): nullable MType
	do
		if col.length == 1 then return col.first
		for t1 in col do
			if t1 == null then continue # return null
			var found = true
			for t2 in col do
				if t2 == null then continue # return null
				if can_be_null(t2) and not can_be_null(t1) then
					t1 = t1.as_nullable
				end
				if not is_subtype(t2, t1) then found = false
			end
			if found then
				#print "merge {col.join(" ")} -> {t1}"
				return t1
			end
		end
		#self.modelbuilder.warning(node, "Type Error: {col.length} conflicting types: <{col.join(", ")}>")
		return null
	end
end

# Mapping between parameters and arguments in a call.
#
# Parameters and arguments are not stored in the class but referenced by their position (starting from 0)
#
# The point of this class is to help engine and other things to map arguments in the AST to parameters of the model.
class SignatureMap
	# Associate a parameter to an argument
	var map = new ArrayMap[Int, Int]
end

# A specific method call site with its associated informations.
class CallSite
	super MEntity

	redef var location: Location

	# The static type of the receiver (possibly unresolved)
	var recv: MType

	# The module where the callsite is present
	var mmodule: MModule

	# The anchor to use with `recv` or `msignature`
	var anchor: nullable MClassType

	# Is the receiver self?
	# If "for_self", virtual types of the signature are kept
	# If "not_for_self", virtual type are erased
	var recv_is_self: Bool

	# The designated method
	var mproperty: MMethod

	# The statically designated method definition
	# The most specif one, it is.
	var mpropdef: MMethodDef

	# The resolved signature for the receiver
	var msignature: MSignature

	# Is a implicit cast required on erasure typing policy?
	var erasure_cast: Bool

	# The mapping used on the call to associate arguments to parameters
	# If null then no specific association is required.
	var signaturemap: nullable SignatureMap = null
end
