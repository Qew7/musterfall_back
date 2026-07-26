module Sim
  module Rng
    class Seeded
      def initialize(seed)
        @state = (seed.to_i & 0xFFFFFFFF) ^ 0xA5A5A5A5
        @state = 1 if @state.zero?
      end

      def rand(max = nil)
        @state ^= (@state << 13) & 0xFFFFFFFF
        @state ^= (@state >> 17)
        @state ^= (@state << 5) & 0xFFFFFFFF
        @state &= 0xFFFFFFFF
        unit = @state.to_f / 0x100000000

        return unit if max.nil?
        return 0 if max.to_i <= 0

        (unit * max.to_i).floor
      end

      def pick(entries)
        return nil if entries.nil? || entries.empty?

        entries[rand(entries.length)]
      end

      def shuffle(entries)
        list = entries.dup
        (list.length - 1).downto(1) do |index|
          swap = rand(index + 1)
          list[index], list[swap] = list[swap], list[index]
        end
        list
      end
    end
  end
end
