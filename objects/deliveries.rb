# frozen_string_literal: true

# Copyright (c) 2019 Yegor Bugayenko
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
require_relative 'delivery'
require_relative 'user_error'

# Deliveries.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018 Yegor Bugayenko
# License:: MIT
class Deliveries
  def initialize(pgsql: Pgsql::TEST)
    @pgsql = pgsql
  end

  def add(campaign, letter, recipient)
    Delivery.new(
      id: @pgsql.exec(
        'INSERT INTO delivery (campaign, letter, recipient) VALUES ($1, $2, $3) RETURNING id',
        [campaign.id, letter.id, recipient.id]
      )[0]['id'].to_i,
      pgsql: @pgsql
    )
  end

  def delivery(id)
    hash = @pgsql.exec('SELECT * FROM delivery WHERE id=$1', [id])[0]
    raise UserError, "Delivery ##{id} not found" if hash.nil?
    Delivery.new(
      id: id,
      pgsql: @pgsql,
      hash: hash
    )
  end
end
