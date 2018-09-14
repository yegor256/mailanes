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
require_relative 'list'

# Lists.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018 Yegor Bugayenko
# License:: MIT
class Lists
  def initialize(owner:, pgsql: Pgsql::TEST)
    @owner = owner
    @pgsql = pgsql
  end

  def count
    @pgsql.exec('SELECT COUNT(id) FROM list WHERE owner=$1', [@owner])[0]['count'].to_i
  end

  def all
    @pgsql.exec('SELECT * FROM list WHERE owner=$1 ORDER BY created DESC', [@owner]).map do |r|
      List.new(id: r['id'].to_i, pgsql: @pgsql, hash: r)
    end
  end

  def add(title = 'noname')
    yaml = "title: #{title}\n"
    List.new(
      id: @pgsql.exec(
        'INSERT INTO list (owner, yaml) VALUES ($1, $2) RETURNING id',
        [@owner, yaml]
      )[0]['id'].to_i,
      pgsql: @pgsql
    )
  end

  def list(id)
    hash = @pgsql.exec(
      'SELECT * FROM list WHERE owner=$1 AND id=$2',
      [@owner, id]
    )[0]
    raise "List ##{id} not found in @#{@owner} account" if hash.nil?
    List.new(
      id: hash['id'].to_i,
      pgsql: @pgsql,
      hash: hash
    )
  end

  def duplicates_count
    @pgsql.exec(
      [
        'SELECT COUNT(*) FROM',
        '(SELECT COUNT(recipient.id) AS dups FROM recipient',
        'JOIN list ON recipient.list = list.id',
        'WHERE list.owner = $1',
        'GROUP BY recipient.email) x',
        'WHERE x.dups > 1'
      ].join(' '),
      [@owner]
    )[0]['count'].to_i
  end
end
