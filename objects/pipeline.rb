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
require_relative 'letter'
require_relative 'recipient'
require_relative 'deliveries'

# Pipeline.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018 Yegor Bugayenko
# License:: MIT
class Pipeline
  def initialize(pgsql: Pgsql.new)
    @pgsql = pgsql
  end

  def fetch(postman)
    @pgsql.exec(
      'DELETE FROM delivery WHERE created < $1 AND details = $2',
      [(Time.now - 60 * 60).strftime('%Y-%m-%d %H:%M:%S'), '']
    )
    deliveries = Deliveries.new(pgsql: @pgsql)
    q = [
      'SELECT DISTINCT recipient.id AS rid, campaign.id AS cid, letter.id AS lid FROM recipient',
      'JOIN list ON list.id=recipient.list',
      'JOIN campaign ON list.id=campaign.list AND campaign.active=true',
      'JOIN lane ON lane.id=campaign.lane',
      'JOIN letter ON lane.id=letter.lane AND letter.active=true',
      'LEFT JOIN delivery AS d ON d.recipient=recipient.id AND d.campaign=campaign.id AND d.letter=letter.id',
      'LEFT JOIN delivery AS r ON r.recipient=recipient.id AND r.campaign=campaign.id AND r.relax > NOW()',
      'WHERE d.id IS NULL AND r.id IS NULL AND recipient.active=true'
    ].join(' ')
    @pgsql.exec(q).each do |r|
      campaign = Campaign.new(id: r['cid'].to_i, pgsql: @pgsql)
      letter = Letter.new(id: r['lid'].to_i, pgsql: @pgsql)
      recipient = Recipient.new(id: r['rid'].to_i, pgsql: @pgsql)
      delivery = deliveries.add(campaign, letter, recipient)
      if letter.yaml['relax']
        time = Time.now
        if letter.yaml['relax'] =~ /[0-9]+:[0-9]+:[0-9]+/
          days, hours, minutes = letter.yaml['relax'].split(':')
          time += (days.to_i * 24 * 60 + hours.to_i * 60 + minutes.to_i) * 60
        elsif letter.yaml['relax'] =~ /[0-9]{2}-[0-9]{2}-[0-9]{4}/
          time = Time.parse(letter.yaml['relax'])
        end
        delivery.relax(time)
      end
      postman.deliver(delivery)
    end
  end

  def deactivate
    @pgsql.exec('SELECT * FROM letter WHERE active=true').each do |r|
      letter = Letter.new(id: r['id'].to_i, pgsql: @pgsql, hash: r)
      letter.toggle if letter.yaml['until'] && Time.parse(letter.yaml['until']) < Time.now
    end
    @pgsql.exec('SELECT * FROM campaign WHERE active=true').each do |r|
      campaign = Campaign.new(id: r['id'].to_i, pgsql: @pgsql, hash: r)
      campaign.toggle if campaign.yaml['until'] && Time.parse(campaign.yaml['until']) < Time.now
    end
  end
end
