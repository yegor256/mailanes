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
require_relative 'campaign'

# Campaigns.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018 Yegor Bugayenko
# License:: MIT
class Campaigns
  def initialize(owner:, pgsql: Pgsql::TEST)
    @owner = owner
    @pgsql = pgsql
  end

  def all
    query = [
      'SELECT campaign.* FROM campaign',
      'JOIN list ON campaign.list=list.id',
      'WHERE list.owner=$1',
      'ORDER BY campaign.created DESC'
    ].join(' ')
    @pgsql.exec(query, [@owner]).map do |r|
      Campaign.new(id: r['id'].to_i, pgsql: @pgsql, hash: r)
    end
  end

  def add(list, lane, title = 'unknown')
    yaml = "title: #{title}\n"
    Campaign.new(
      id: @pgsql.exec(
        'INSERT INTO campaign (list, lane, yaml) VALUES ($1, $2, $3) RETURNING id',
        [list.id, lane.id, yaml]
      )[0]['id'].to_i,
      pgsql: @pgsql
    )
  end

  def campaign(id)
    hash = @pgsql.exec(
      'SELECT campaign.* FROM campaign JOIN list ON campaign.list=list.id WHERE campaign.id=$1 AND list.owner=$2',
      [id, @owner]
    )[0]
    Campaign.new(
      id: hash['id'].to_i,
      pgsql: @pgsql,
      hash: hash
    )
  end
end
