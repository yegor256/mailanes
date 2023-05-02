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
