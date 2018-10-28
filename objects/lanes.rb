# frozen_string_literal: true

# Copyright (c) 2018 Yegor Bugayenko
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
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

require_relative 'pgsql'
require_relative 'lane'

# Lanes.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018 Yegor Bugayenko
# License:: MIT
class Lanes
  def initialize(owner:, pgsql: Pgsql::TEST)
    @owner = owner
    @pgsql = pgsql
  end

  def count
    @pgsql.exec('SELECT COUNT(id) FROM lane WHERE owner=$1', [@owner])[0]['count'].to_i
  end

  def all
    @pgsql.exec('SELECT * FROM lane WHERE owner=$1 ORDER BY created DESC', [@owner]).map do |r|
      Lane.new(id: r['id'].to_i, pgsql: @pgsql, hash: r)
    end
  end

  def add(title = 'unknown')
    yaml = "title: #{title}\n"
    Lane.new(
      id: @pgsql.exec(
        'INSERT INTO lane (owner, yaml) VALUES ($1, $2) RETURNING id',
        [@owner, yaml]
      )[0]['id'].to_i,
      pgsql: @pgsql
    )
  end

  def lane(id)
    hash = @pgsql.exec(
      'SELECT * FROM lane WHERE owner=$1 AND id=$2',
      [@owner, id]
    )[0]
    raise "Lane ##{id} not found @#{@owner} account" if hash.nil?
    Lane.new(
      id: hash['id'].to_i,
      pgsql: @pgsql,
      hash: hash
    )
  end

  def letter(id, tbot: Tbot.new)
    hash = @pgsql.exec(
      [
        'SELECT letter.* FROM letter',
        'JOIN lane ON letter.lane = lane.id',
        'WHERE lane.owner=$1 AND letter.id=$2'
      ].join(' '),
      [@owner, id]
    )[0]
    raise "Letter ##{id} not found in any lanes owned by @#{@owner}" if hash.nil?
    Letter.new(
      id: hash['id'].to_i,
      pgsql: @pgsql,
      hash: hash,
      tbot: tbot
    )
  end
end
