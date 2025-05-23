# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Yegor Bugayenko
# SPDX-License-Identifier: MIT

require 'yaml'
require_relative 'test__helper'
require_relative '../objects/yaml_doc'
require_relative '../objects/user_error'

class YamlDocTest < Minitest::Test
  def test_loads_valid_yaml
    yaml = YamlDoc.new("title: \"Test\"\nage: 25").load
    assert_equal(25, yaml['age'])
  end

  def test_checks_emptiness
    assert_empty(YamlDoc.new(''))
    assert_empty(YamlDoc.new("---\n"))
    refute_empty(YamlDoc.new("a: b\n"))
  end

  def test_saves_valid_yaml
    text = YamlDoc.new("title: \"Test\"\nage: 25").save
    assert_includes(text, 'title: Test', text)
  end

  def test_safely_loads_broken_yaml
    assert_kind_of(Hash, YamlDoc.new('\"oops...').load)
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
