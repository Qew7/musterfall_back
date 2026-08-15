module BattleInvariants
  EPSILON = 0.08

  class Violation < StandardError; end

  module_function

  def verify_result!(result, terrain: nil)
    verify_battlefield!(
      [ result.acting_side, result.target_side ],
      terrain: terrain || result.scenario[:terrain]
    )
    result.actions.each { |action| verify_movement_action!(action) }
    true
  end

  def verify_battlefield!(sides, terrain: [])
    units = Array(sides).flat_map { |side| Array(side[:combatants]) }
      .select { |unit| unit[:current_health].to_i > 0 }

    units.each do |unit|
      verify_pose!(unit)
      verify_health_and_footprint!(unit)
    end

    units.combination(2) do |left, right|
      next unless Sim::Geometry::Battlefield.rectangles_overlap?(left, right)

      fail!("#{label(left)} overlaps #{label(right)}")
    end

    obstacles = Sim::Geometry::Battlefield.impassable_obstacles(terrain)
    units.each do |unit|
      obstacles.each do |obstacle|
        next unless Sim::Geometry::Battlefield.rectangles_overlap?(unit, obstacle)

        fail!("#{label(unit)} overlaps impassable terrain #{label(obstacle)}")
      end
    end
    true
  end

  def verify_movement_action!(action)
    required = %i[type actor_id actor_state_before actor_state_after summary details from to maneuver]
    missing = required.reject { |key| action.key?(key) }
    fail!("movement action missing #{missing.join(', ')}") if missing.any?
    fail!("unexpected action type #{action[:type].inspect}") unless action[:type].to_s == "movement"

    verify_point!(action[:from], "action.from")
    verify_point!(action[:to], "action.to")
    fail!("movement action details must be an array") unless action[:details].is_a?(Array)
    fail!("movement maneuver must have a kind") if action.dig(:maneuver, :kind).to_s.empty?

    budget = action.dig(:maneuver, :mv_budget)
    return true if budget.nil?

    wheel = action.dig(:maneuver, :mv_spent_wheel).to_f
    turn = action.dig(:maneuver, :mv_spent_turn).to_f
    advance = action.dig(:maneuver, :mv_spent_advance).to_f
    march = action.dig(:maneuver, :mv_spent_march).to_f
    fail!("negative movement cost") if [ wheel, turn, advance, march ].any? { |cost| cost < -EPSILON }
    if wheel + turn + advance + march > budget.to_f + EPSILON
      fail!("movement cost #{wheel + turn + advance + march} exceeds budget #{budget}")
    end
    true
  end

  def verify_pose!(unit)
    verify_point!(unit, label(unit))
    width = Sim::Geometry::Battlefield::CONFIG[:width].to_f
    height = Sim::Geometry::Battlefield::CONFIG[:height].to_f
    unless unit[:x].to_f.between?(0.0, width) && unit[:y].to_f.between?(0.0, height)
      fail!("#{label(unit)} is outside battlefield")
    end
  end

  def verify_health_and_footprint!(unit)
    health = unit[:current_health].to_f
    max_health = unit[:max_health]
    fail!("#{label(unit)} has negative health") if health.negative?
    if max_health && health > max_health.to_f + EPSILON
      fail!("#{label(unit)} health exceeds max_health")
    end

    %i[base_width base_depth].each do |key|
      fail!("#{label(unit)} has invalid #{key}") unless unit[key].to_f.positive?
    end
    if unit.key?(:models_remaining) && unit[:models_remaining].to_i.negative?
      fail!("#{label(unit)} has negative models_remaining")
    end
  end

  def verify_pathing_plan!(origin, plan, obstacles: [], budget: nil, contact_id: nil)
    fail!("pathing plan missing pose") unless plan && plan[:pose]

    landed = Sim::Geometry::Battlefield.merge_footprint(origin, plan[:pose])
    Array(obstacles).each do |obstacle|
      next if obstacle[:entity_id] == origin[:entity_id]
      next if contact_id && obstacle[:entity_id] == contact_id

      next unless Sim::Geometry::Battlefield.rectangles_overlap?(landed, obstacle)

      fail!("#{label(origin)} overlaps #{label(obstacle)}")
    end
    true
  end

  def verify_point!(point, context)
    fail!("#{context} must be a hash") unless point.is_a?(Hash)
    %i[x y facing].each do |key|
      value = point[key]
      fail!("#{context}.#{key} is not finite") unless value.is_a?(Numeric) && value.finite?
    end
  end

  def label(entity)
    entity[:name] || entity[:entity_id] || entity[:id] || "entity"
  end

  def fail!(message)
    raise Violation, message
  end
end
