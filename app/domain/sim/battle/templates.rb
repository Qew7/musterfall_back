module Sim
  module Battle
    module Templates
      KINDS = {
        "breath" => Breath,
        "line" => Line
      }.freeze

      module_function

      def build(kind, attacker, primary_target)
        KINDS.fetch(kind.to_s).new(attacker, primary_target)
      end
    end
  end
end
