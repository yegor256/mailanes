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
require_relative 'letter'
require_relative 'tbot'
require_relative 'user_error'

# Letters.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018 Yegor Bugayenko
# License:: MIT
class Letters
  def initialize(lane:, pgsql: Pgsql::TEST)
    @lane = lane
    @pgsql = pgsql
  end

  def count
    @pgsql.exec('SELECT COUNT(id) FROM letter WHERE lane=$1', [@lane.id])[0]['count'].to_i
  end

  def all
    @pgsql.exec('SELECT * FROM letter WHERE lane=$1 ORDER BY place DESC, created DESC', [@lane.id]).map do |r|
      Letter.new(id: r['id'].to_i, pgsql: @pgsql, hash: r)
    end
  end

  def add(title = 'undefined', tbot: Tbot.new)
    yaml = "title: #{title}\n"
    Letter.new(
      id: @pgsql.exec(
        'INSERT INTO letter (lane, yaml) VALUES ($1, $2) RETURNING id',
        [@lane.id, yaml]
      )[0]['id'].to_i,
      pgsql: @pgsql,
      tbot: tbot
    )
  end

  def letter(id, tbot: Tbot.new)
    hash = @pgsql.exec('SELECT * FROM letter WHERE lane=$1 AND id=$2', [@lane.id, id])[0]
    raise UserError, "Letter ##{id} not found in the lane ##{@lane.id}" if hash.nil?
    Letter.new(
      id: hash['id'].to_i,
      pgsql: @pgsql,
      hash: hash,
      tbot: tbot
    )
  end
end
