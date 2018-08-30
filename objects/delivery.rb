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

# Delivery.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018 Yegor Bugayenko
# License:: MIT
class Delivery
  attr_reader :id

  def initialize(id:, pgsql: Pgsql.new, hash: {})
    raise "Invalid ID: #{id} (#{id.class.name})" unless id.is_a?(Integer)
    @id = id
    @pgsql = pgsql
    @hash = hash
  end

  def recipient
    hash = @pgsql.exec(
      'SELECT recipient.* FROM recipient JOIN delivery ON delivery.recipient=recipient.id WHERE delivery.id=$1',
      [@id]
    )[0]
    Recipient.new(
      id: hash['id'].to_i,
      pgsql: @pgsql,
      hash: hash
    )
  end

  def letter
    hash = @pgsql.exec(
      'SELECT letter.* FROM letter JOIN delivery ON delivery.letter=letter.id WHERE delivery.id=$1',
      [@id]
    )[0]
    Letter.new(
      id: hash['id'].to_i,
      pgsql: @pgsql,
      hash: hash
    )
  end

  def campaign
    hash = @pgsql.exec(
      'SELECT campaign.* FROM campaign JOIN delivery ON delivery.campaign=campaign.id WHERE delivery.id=$1',
      [@id]
    )[0]
    Campaign.new(
      id: hash['id'].to_i,
      pgsql: @pgsql,
      hash: hash
    )
  end

  def details
    @hash['details'] || @pgsql.exec('SELECT details FROM delivery WHERE id=$1', [@id])[0]['details']
  end

  def close(details)
    @pgsql.exec('UPDATE delivery SET details=$1 WHERE id=$2', [details, @id])
    @hash = {}
  end
end
