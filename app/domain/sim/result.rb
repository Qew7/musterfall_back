module Sim
  class Result
    attr_reader :value, :error, :code

    def self.ok(value = nil)
      new(ok: true, value: value)
    end

    def self.failure(error, code: :unprocessable)
      new(ok: false, error: error, code: code)
    end

    def initialize(ok:, value: nil, error: nil, code: nil)
      @ok = ok
      @value = value
      @error = error
      @code = code
    end

    def ok?
      @ok
    end

    def failure?
      !@ok
    end
  end
end
