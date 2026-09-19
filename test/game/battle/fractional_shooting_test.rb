require "test_helper"

class FractionalShootingTest < ActiveSupport::TestCase
  Attack = Sim::Battle::Phases::AttackResolution
  State = Sim::Battle::State

  setup do
    @shooter = combatant(entity_id: "archer", actor_id: "archer", host_id: "archer",
      actor_name: "Archer", actor_role: "unit", ranged: 1, weapon_type: "ranged",
      shooting_template: "common", missile_attacks: 1, skill: 7, files: 2)
    @target = enemy(entity_id: "target", current_health: 1, max_health: 1,
      models_remaining: 1, starting_models: 1, armor_type: nil, cost: 100)
    @rng = Object.new
    @rng.define_singleton_method(:rand) { |*_args| 0.0 }
  end

  test "fractional hits accumulate only within a volley and its remainder is discarded" do
    @shooter.merge!(ranged: 2, missile_attacks: 2)
    @target.merge!(current_health: 10, max_health: 10, starting_models: 10, models_remaining: 10)
    phase = shoot
    assert_equal 1, phase[:actions].size
    assert_equal 3, phase[:actions].first[:damage] # 4 * 1.8 / 2.2 = 3.2727...
    assert_equal 7, @target[:current_health]
    assert_equal 7, @target[:models_remaining]
    shoot
    assert_equal 4, @target[:current_health]
    assert_equal 4, @target[:models_remaining]
  end

  test "sub-one volleys never injure a model or accumulate across attacks" do
    4.times do
      action = shoot[:actions].first
      assert_equal 0, action[:damage]
      assert_equal 2, action[:hits_landed]
      assert_equal 1, @target[:current_health]
      assert_equal 1, @target[:models_remaining]
    end
  end

  test "volley floors each target after the secondary multiplier" do
    @shooter.merge!(shooting_template: "volley", ranged: 5)
    @target.merge!(current_health: 10, max_health: 10)
    secondary = enemy(entity_id: "secondary", x: @target[:x], y: @target[:y] + 1,
      current_health: 10, armor_type: nil)
    phase = shoot([ @target, secondary ])
    assert_equal [ 4, 2 ], phase[:actions].map { |action| action[:damage] }
    assert_equal 8, secondary[:current_health] # 4.09... * 0.65 = 2.659..., not 3
    estimate = Sim::Battle::Rules::Volley::Shooting.expected_damage(@shooter, @target, "front", 1, "shooting", [ @target, secondary ])
    assert_in_delta 6, estimate, 1e-12
  end

  test "AI averages the applied integer damage over possible hit counts" do
    # Two half-HP hits are required; both hit with probability 0.25.
    assert_in_delta 0.25, Sim::Battle::Rules::Common::Shooting.expected_volley_damage(2, 0.5, 0.6, 10), 1e-12
  end

  test "hit effects remain separate from whole HP damage and misses do not apply them" do
    @shooter[:abilities] = [ "toxin" ]
    action = shoot[:actions].first
    assert_equal 0, action[:damage]
    assert @target[:toxin_weakened]
    @target.delete(:toxin_weakened)
    @rng.define_singleton_method(:rand) { |*_args| 1.0 }
    action = shoot[:actions].first
    assert_equal 0, action[:hits_landed]
    assert_equal 1, @target[:current_health]
    refute @target[:toxin_weakened]
  end

  test "geometric templates and melee retain integer per hit damage" do
    %w[line breath blast single].each do |template|
      value = Attack.damage(@shooter.merge(shooting_template: template), @target, "shooting", "front", 1)
      assert_kind_of Integer, value
    end
    assert_kind_of Integer, Attack.damage(@shooter, @target, "melee", "front", 1)
  end

  private

  def shoot(targets = [ @target ])
    phase = Attack.create_phase("shooting", "Shooting")
    Attack.resolve_missile_strike!(phase: phase, actor: @shooter, target: @target,
      vector: "front", attack_type: "shooting", round_number: 1, rng: @rng,
      acting_side: { combatants: [ @shooter ] }, target_side: { combatants: targets })
    phase
  end
end
