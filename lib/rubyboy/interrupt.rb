# frozen_string_literal: true

require 'json'

module Rubyboy
  class Interrupt
    attr_accessor :ie, :if

    def initialize
      @ie = 0
      @if = 0
    end

    def read_byte(addr)
      case addr
      when 0xff0f
        @if
      when 0xffff
        @ie
      end
    end

    def write_byte(addr, value)
      case addr
      when 0xff0f
        @if = value
      when 0xffff
        @ie = value
      end
    end

    def interrupts
      @if & @ie & 0x1f
    end

    def request(interrupt)
      @if |= interrupt
    end
  end
end
