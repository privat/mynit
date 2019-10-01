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

# Test the creation ans the usage on simply contract, in the same time check the no modification of the parameter.
# See the `foo` method in `Myclass` the change of x in a body method has no effect on the ensure because x is a primitive type and it's given by copy and not by reference.

class MyClass
	fun foo(x: Int)
	is
		expects(x == 1)
		ensures(x > 0)
	do
		x = 0
	end
end

class MyClass2
	fun foo(bool: Bool)
	is
		expects(not bool)
		ensures(not bool)
	do
		if bool then print "Error"
	end
end

var first = new MyClass
first.foo(1)
var second = new MyClass2
second.foo(true) #Fail