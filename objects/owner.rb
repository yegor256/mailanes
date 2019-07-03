# frozen_string_literal: true

# Copyright (c) 2018-2019 Yegor Bugayenko
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

require_relative 'lists'
require_relative 'lanes'
require_relative 'campaigns'
require_relative 'deliveries'

# Owner.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018-2019 Yegor Bugayenko
# License:: MIT
class Owner
  def initialize(login:, pgsql:)
    @login = login
    @pgsql = pgsql
  end

  def lists
    Lists.new(owner: @login, pgsql: @pgsql)
  end

  def lanes
    Lanes.new(owner: @login, pgsql: @pgsql)
  end

  def campaigns
    Campaigns.new(owner: @login, pgsql: @pgsql)
  end

  def deliveries
    Deliveries.new(pgsql: @pgsql)
  end

  def months(source)
    @pgsql.exec(
      [
        'SELECT CONCAT(DATE_PART(\'year\', recipient.created), \'/\',',
        '  DATE_PART(\'month\', recipient.created)) AS month,',
        'COUNT(recipient.*) AS total,',
        'COUNT(recipient.*) FILTER (WHERE bounced IS NOT NULL) as bad',
        'FROM recipient',
        'LEFT JOIN delivery ON recipient.id = delivery.recipient',
        'WHERE source = $1',
        'GROUP BY month',
        'ORDER BY month DESC'
      ].join(' '),
      [source.downcase.strip]
    ).map { |r| { month: r['month'], total: r['total'].to_i, bad: r['bad'].to_i } }
  end
end
