# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Yegor Bugayenko
# SPDX-License-Identifier: MIT

require 'minitest/autorun'
require_relative 'test__helper'
require_relative '../objects/owner'

class OwnerTest < Minitest::Test
  def test_monthly_contribution
    login = random_owner
    source = "src-#{rand(999)}"
    owner = Owner.new(pgsql: t_pgsql, login: login)
    assert_equal(0, owner.months(source).count)
    list = Lists.new(owner: login, pgsql: t_pgsql).add
    recipients = Recipients.new(list: list, pgsql: t_pgsql)
    total = 3
    total.times do |i|
      recipients.add("test#{i}@mailanes.com", source: source)
    end
    data = owner.months(source)
    assert_equal(total, data[0][:total])
  end
end
