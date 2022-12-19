# frozen_string_literal: true

# Copyright (c) 2018-2022 Yegor Bugayenko
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

require_relative 'list'
require_relative 'user_error'

# Lists.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018-2022 Yegor Bugayenko
# License:: MIT
class Lists
  def initialize(owner:, pgsql:)
    @owner = owner
    @pgsql = pgsql
  end

  def count
    @pgsql.exec('SELECT COUNT(*) FROM list WHERE owner=$1', [@owner])[0]['count'].to_i
  end

  def all
    found = @pgsql.exec(
      [
        'SELECT list.id, COUNT(recipient.id) AS total_recipients',
        'FROM recipient',
        'JOIN list ON list.id = recipient.list',
        'WHERE list.owner = $1',
        'GROUP BY list.id',
        'ORDER BY list.created DESC'
      ],
      [@owner]
    ).map { |r| List.new(id: r['id'].to_i, pgsql: @pgsql, hash: r) }
    ids = @pgsql.exec('SELECT list.id FROM list WHERE owner=$1', [@owner]).map { |r| r['id'].to_i }
    ids.each do |id|
      found << List.new(id: id, pgsql: @pgsql) unless found.find { |l| l.id == id }
    end
    found
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
    raise UserError, "List ##{id} not found in @#{@owner} account" if hash.nil?
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
        '(SELECT COUNT(1) AS dups FROM recipient',
        'JOIN list ON recipient.list = list.id',
        'WHERE list.owner = $1 AND list.stop = false',
        'GROUP BY recipient.email) x',
        'WHERE x.dups > 1'
      ],
      [@owner]
    )[0]['count'].to_i
  end

  def total_recipients
    @pgsql.exec(
      [
        'SELECT COUNT(recipient.email) FROM recipient',
        'JOIN list ON recipient.list = list.id',
        'WHERE list.owner = $1 AND list.stop = false'
      ],
      [@owner]
    )[0]['count'].to_i
  end

  # Deactivate them all
  def deactivate_recipients(emails)
    @pgsql.exec(
      [
        'UPDATE recipient SET active = false',
        'FROM list',
        'WHERE list.owner = $1 AND recipient.email IN (',
        emails.map { |e| "'#{e.gsub(/'/, '\\\'')}'" }.join(', '),
        ')'
      ],
      [@owner]
    )
  end
end
