module Sim
  module Battle
    module Rules
      module Toxin
        # rule: toxin | shared | First hit permanently −1 skill and −1 melee on target (and primary contributor).
        module_function

        def apply!(ctx)
          defender = ctx[:defender]
          return unless [ ctx[:attacker], ctx[:host] ].compact.any? { |entry| Array(entry[:abilities]).include?("toxin") }
          return if defender[:toxin_weakened]

          defender[:toxin_weakened] = true
          defender[:skill] = [ defender[:skill].to_i - 1, 1 ].max
          defender[:melee] = [ defender[:melee].to_i - 1, 0 ].max
          primary = Array(defender.dig(:contributors, :melee)).first
          if primary
            primary[:skill] = [ primary[:skill].to_i - 1, 1 ].max
            primary[:power] = [ primary[:power].to_i - 1, 0 ].max
          end
          action = ctx[:action]
          (action[:details] ||= []) << "toxin skill=-1 melee=-1"
          ActionResult.append_clause!(action, "токсин снижает SK и ML цели на 1 до конца боя")
        end
      end
    end
  end
end
