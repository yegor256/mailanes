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

require 'yaml'
require_relative 'pgsql'
require_relative 'recipients'
require_relative 'campaign'

# List.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018 Yegor Bugayenko
# License:: MIT
class List
  attr_reader :id

  def initialize(id:, pgsql: Pgsql.new, hash: {})
    raise "Invalid ID: #{id} (#{id.class.name})" unless id.is_a?(Integer)
    @id = id
    @pgsql = pgsql
    @hash = hash
  end

  def recipients
    Recipients.new(list: self, pgsql: @pgsql)
  end

  def title
    yaml['title'] || 'unknown'
  end

  def yaml
    YAML.safe_load(
      @hash['yaml'] || @pgsql.exec('SELECT yaml FROM list WHERE id=$1', [@id])[0]['yaml']
    )
  end

  def save_yaml(yaml)
    yml = YAML.safe_load(yaml)
    @pgsql.exec('UPDATE list SET yaml=$1 WHERE id=$2', [yaml, @id])
    stop = yml['stop']
    @pgsql.exec('UPDATE list SET stop=$1 WHERE id=$2', [stop, @id])
    @hash = {}
  end

  def stop?
    (@hash['stop'] || @pgsql.exec('SELECT stop FROM list WHERE id=$1', [@id])[0]['stop']) == 't'
  end

  def friend?(login)
    friends = yaml['friends']
    return false unless friends.is_a?(Array)
    friends.include?(login)
  end

  def campaigns
    @pgsql.exec('SELECT * FROM campaign WHERE campaign.list=$1 ORDER BY created DESC', [@id]).map do |r|
      Campaign.new(id: r['id'].to_i, pgsql: @pgsql, hash: r)
    end
  end

  def deliveries_count
    @pgsql.exec(
      [
        'SELECT COUNT(*) FROM delivery',
        'JOIN recipient ON recipient.id=delivery.recipient',
        'JOIN list ON recipient.list=list.id',
        'WHERE list.id=$1'
      ].join(' '),
      [@id]
    )[0]['count'].to_i
  end
end
