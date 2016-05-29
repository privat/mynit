# This file is part of NIT ( http://www.nitlanguage.org ).
#
# This file is free software, which comes along with NIT.  This software is
# distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
# without  even  the implied warranty of  MERCHANTABILITY or  FITNESS FOR A
# PARTICULAR PURPOSE.  You can modify it is you want,  provided this header
# is kept unaltered, and a notification of the changes is added.
# You  are  allowed  to  redistribute it and sell it, alone or is a part of
# another product.

# Primitive services to display more information on `assert`
#
# To be effective, the engines should be teach to use them.
module assert_utils
import file

# Display an error message when `name` is called with `args`
fun assert_call_failed(name: String, args: Array[nullable Object])
do
	print_error "Called {name} with"
	var i = 0
	while i < args.length do
		var na = args[i].as(not null)
		var ea = inspect_obj(args[i+1])
		print_error "\t* {na}: {ea}"
		i += 2
	end
end

# A descriptive information on an object.
fun inspect_obj(no: nullable Object): String
do
	if no == null then return "null"
	var s = no.to_s
	var i = no.inspect
	if s == i then return s
	if s.length > 40 then
		s = s.substring(0, 40) + "..."
	end
	s += " (#{no.inspect})"
	return s
end
