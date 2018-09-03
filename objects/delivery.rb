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
    id = @hash['recipient'] || @pgsql.exec('SELECT recipient FROM delivery WHERE id=$1', [@id])[0]['recipient']
    Recipient.new(
      id: id.to_i,
      pgsql: @pgsql
    )
  end

  def letter
    id = @hash['letter'] || @pgsql.exec('SELECT letter FROM delivery WHERE id=$1', [@id])[0]['letter']
    Letter.new(
      id: id.to_i,
      pgsql: @pgsql
    )
  end

  def campaign
    id = @hash['campaign'] || @pgsql.exec('SELECT campaign FROM delivery WHERE id=$1', [@id])[0]['campaign']
    Campaign.new(
      id: id.to_i,
      pgsql: @pgsql
    )
  end

  def details
    @hash['details'] || @pgsql.exec('SELECT details FROM delivery WHERE id=$1', [@id])[0]['details']
  end

  def close(details)
    @pgsql.exec('UPDATE delivery SET details=$1 WHERE id=$2', [details, @id])
    @hash = {}
  end

  def save_relax(time)
    @pgsql.exec('UPDATE delivery SET relax=$1 WHERE id=$2', [time.strftime('%Y-%m-%d %H:%M:%S'), @id])
    @hash = {}
  end

  def relax
    @hash['relax'] || @pgsql.exec('SELECT relax FROM delivery WHERE id=$1', [@id])[0]['relax']
  end
end
