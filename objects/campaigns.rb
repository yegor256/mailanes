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
    @pgsql.exec('SELECT * FROM campaign WHERE owner=$1 ORDER BY created DESC', [@owner]).map do |r|
      Campaign.new(id: r['id'].to_i, pgsql: @pgsql, hash: r)
    end
  end

  def add(list, lane, title = 'unknown')
    yaml = "title: #{title}\n"
    campaign = Campaign.new(
      id: @pgsql.exec(
        'INSERT INTO campaign (owner, lane, yaml) VALUES ($1, $2, $3) RETURNING id',
        [@owner, lane.id, yaml]
      )[0]['id'].to_i,
      pgsql: @pgsql
    )
    campaign.add(list)
    campaign
  end

  def campaign(id)
    hash = @pgsql.exec(
      'SELECT * FROM campaign WHERE id=$1 AND owner=$2',
      [id, @owner]
    )[0]
    Campaign.new(
      id: hash['id'].to_i,
      pgsql: @pgsql,
      hash: hash
    )
  end

  def total_deliveries(days = 7)
    @pgsql.exec(
      [
        'SELECT COUNT(delivery.id) FROM delivery',
        'JOIN campaign ON delivery.campaign = campaign.id',
        "WHERE campaign.owner = $1 AND delivery.created > NOW() - INTERVAL \'#{days} DAYS\'"
      ].join(' '),
      [@owner]
    )[0]['count'].to_i
  end

  def total_bounced(days = 7)
    @pgsql.exec(
      [
        'SELECT COUNT(recipient.id) FROM recipient',
        'JOIN list ON recipient.list = list.id',
        "WHERE list.owner = $1 AND recipient.bounced > NOW() - INTERVAL \'#{days} DAYS\'"
      ].join(' '),
      [@owner]
    )[0]['count'].to_i
  end
end
