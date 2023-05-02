# frozen_string_literal: true

# Copyright (c) 2018-2023 Yegor Bugayenko
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the 'Software'), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

require 'minitest/autorun'
require 'yaml'
require_relative 'test__helper'
require_relative '../objects/yaml_doc'
require_relative '../objects/user_error'

class YamlDocTest < Minitest::Test
  def test_loads_valid_yaml
    yaml = YamlDoc.new("title: \"Test\"\nage: 25").load
    assert_equal(25, yaml['age'])
  end

  def test_saves_valid_yaml
    text = YamlDoc.new("title: \"Test\"\nage: 25").save
    assert(text.include?('title: Test'), text)
  end

  def test_safely_loads_broken_yaml
    assert(YamlDoc.new('\"oops...').load.is_a?(Hash))
  end

  def test_rejects_broken_yaml
    assert_raises(UserError) do
      YamlDoc.new('this is not yaml').save
    end
  end

  def test_rejects_broken_yaml_syntax
    assert_raises(UserError) do
      YamlDoc.new('\"oops...').save
    end
  end
end
