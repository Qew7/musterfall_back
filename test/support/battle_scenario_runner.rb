class BattleScenarioRunner
  Result = Struct.new(
    :scenario,
    :acting_side,
    :target_side,
    :phases,
    :pose_signatures,
    :reached,
    :stuck_reason,
    keyword_init: true
  ) do
    def actor
      acting_side[:combatants].find { |entry| entry[:entity_id] == scenario[:actor_id] }
    end

    def target
      target_side[:combatants].find { |entry| entry[:entity_id] == scenario[:target_id] }
    end

    def actions
      phases.flat_map { |phase| Array(phase[:actions]) }
    end
  end

  def initialize(scenario)
    @scenario = deep_dup(scenario)
  end

  def run_movement_turns(max_turns: @scenario[:max_turns])
    acting_side = { player_id: "left", combatants: deep_dup(@scenario[:left]) }
    target_side = { player_id: "right", combatants: deep_dup(@scenario[:right]) }
    phases = []
    signatures = []
    stuck_reason = nil

    max_turns.to_i.times do |index|
      actor = find_unit(acting_side, @scenario[:actor_id])
      target = find_unit(target_side, @scenario[:target_id])
      break if engaged?(actor, target)

      signature = pose_signature(actor)
      if signatures.include?(signature)
        stuck_reason = :pose_cycle
        break
      end
      signatures << signature

      phase = Sim::Battle::Phases::Movement.play(
        acting_side: acting_side,
        target_side: target_side,
        round_number: index + 1,
        terrain: deep_dup(@scenario[:terrain])
      )
      phases << phase

      after_signature = pose_signature(actor)
      if after_signature == signature && board_unchanged?(acting_side, target_side, signatures)
        stuck_reason = :no_progress
        break
      end
    end

    actor = find_unit(acting_side, @scenario[:actor_id])
    target = find_unit(target_side, @scenario[:target_id])
    Result.new(
      scenario: @scenario,
      acting_side: acting_side,
      target_side: target_side,
      phases: phases,
      pose_signatures: signatures,
      reached: engaged?(actor, target),
      stuck_reason: stuck_reason
    )
  end

  def run_movement_phase
    run_movement_turns(max_turns: 1)
  end

  private

  def find_unit(side, entity_id)
    side[:combatants].find { |entry| entry[:entity_id] == entity_id }
  end

  def engaged?(actor, target)
    actor && target && Sim::Battle::Decisions::Movement.engaged?(actor, target)
  end

  def pose_signature(unit)
    return nil unless unit

    [
      unit[:entity_id],
      unit[:x].to_f.round(3),
      unit[:y].to_f.round(3),
      Sim::Geometry::Battlefield.normalize_facing(unit[:facing]).round(2)
    ]
  end

  def board_unchanged?(_acting_side, _target_side, signatures)
    signatures.length >= 1
  end

  def deep_dup(value)
    Marshal.load(Marshal.dump(value))
  end
end
