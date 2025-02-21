# frozen_string_literal: true

# SPDX-FileCopyrightText: Copyright (c) 2018-2025 Yegor Bugayenko
# SPDX-License-Identifier: MIT

# String in hex and the other way around.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2018-2025 Yegor Bugayenko
# License:: MIT
class Hex
  # From text to hex.
  class FromText
    def initialize(text)
      @text = text
    end

    # Turn it into a string.
    def to_s
      @text.unpack('U' * @text.length).collect { |x| x.to_s(16) }.join
    end
  end

  # From hex to text.
  class ToText
    def initialize(hex)
      @hex = hex
    end

    # Turn it into a string.
    def to_s
      [@hex].pack('H*').force_encoding('UTF-8')
    end
  end
end
