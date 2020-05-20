# frozen_string_literal: true

# Copyright (c) 2018-2020 Yegor Bugayenko
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

require 'yaml'
require_relative 'letters'
require_relative 'yaml_doc'

# Lane.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018-2020 Yegor Bugayenko
# License:: MIT
class Lane
  attr_reader :id

  def initialize(id:, pgsql:, hash: {})
    raise "Invalid ID: #{id} (#{id.class.name})" unless id.is_a?(Integer)
    @id = id
    @pgsql = pgsql
    @hash = hash.dup
  end

  def letters
    Letters.new(lane: self, pgsql: @pgsql)
  end

  def title
    yaml['title'] || 'unknown'
  end

  def yaml
    YamlDoc.new(
      @hash['yaml'] || @pgsql.exec('SELECT yaml FROM lane WHERE id=$1', [@id])[0]['yaml']
    ).load
  end

  def yaml=(yaml)
    @pgsql.exec('UPDATE lane SET yaml=$1 WHERE id=$2', [YamlDoc.new(yaml).save, @id])
    @hash = {}
  end

  def deliveries_count
    @pgsql.exec(
      [
        'SELECT COUNT(*) FROM delivery',
        'JOIN letter ON letter.id = delivery.letter',
        'WHERE letter.lane = $1'
      ].join(' '),
      [@id]
    )[0]['count'].to_i
  end
end
