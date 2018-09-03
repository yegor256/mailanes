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
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

require 'minitest/autorun'
require 'rack/test'
require 'yaml'
require 'tempfile'
require_relative 'test__helper'
require_relative '../objects/lists'
require_relative '../objects/recipients'

class RecipientsTest < Minitest::Test
  def test_creates_recipients
    owner = random_owner
    lists = Lists.new(owner: owner)
    list = lists.add
    recipients = Recipients.new(list: list)
    recipient = recipients.add('test@mailanes.com')
    assert(recipient.id > 0)
    assert_equal(1, recipients.all.count)
  end

  def test_count_by_source
    owner = random_owner
    lists = Lists.new(owner: owner)
    list = lists.add
    recipients = Recipients.new(list: list)
    source = 'xxx'
    recipients.add('tes-7@mailanes.com', source: source)
    assert_equal(1, recipients.count_by_source(source))
  end

  def test_upload_recipients
    owner = random_owner
    lists = Lists.new(owner: owner)
    list = lists.add
    recipients = Recipients.new(list: list)
    Tempfile.open do |f|
      File.write(
        f.path,
        [
          'test@example.com,Jeff,Lebowski',
          'test2@example.com,Walter,Sobchak'
        ].join("\n")
      )
      recipients.upload(f.path)
    end
    assert_equal(2, recipients.all.count)
  end
end
