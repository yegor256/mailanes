# frozen_string_literal: true

# Copyright (c) 2019 Yegor Bugayenko
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
require 'rack/test'
require 'threads'
require_relative 'test__helper'
require_relative '../objects/pgsql'

class PgsqlTest < Minitest::Test
  def test_retrieves_lists
    db = Pgsql::TEST
    db.connect do |c|
      c.exec('SELECT * FROM list') do |r|
        # later
      end
    end
  end

  def test_handles_many_connections
    db = Pgsql::TEST
    1000.times do
      db.exec('SELECT * FROM list')
    end
  end

  def test_handles_many_threads
    db = Pgsql::TEST
    lists = Lists.new(owner: random_owner)
    list = lists.add
    Threads.new(25).assert(100) do
      db.exec('SELECT * FROM list WHERE id=$1', [list.id]).each do |r|
        r['id'].to_i
      end
    end
  end
end
