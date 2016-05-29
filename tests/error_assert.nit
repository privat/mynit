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

redef class Object
	# Remove `object_id` as it is not reproducible
	redef fun inspect_head do return class_name
end

var abc = "abc"
var ab = "ab"
var f = false
#alt1# assert abc == ab
#alt2# assert not abc == abc
#alt3# assert abc.is_empty
#alt4# assert not "".is_empty
#alt5# assert abc.chars.has_exactly(ab.chars)
#alt6# assert not abc.chars.has_exactly(abc.chars)
#alt7# assert f
#alt8# assert not f
