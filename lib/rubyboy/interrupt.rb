# frozen_string_literal: true

require 'json'

module Rubyboy
  class Interrupt
    attr_accessor :ie, :if

    def initialize
      @ie = 0
      @if = 0
    end

    def interrupts
      @if & @ie & 0x1f
    end

    def request(interrupt)
      @if |= interrupt
    end
  end
end
