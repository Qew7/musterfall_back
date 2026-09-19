require "test_helper"

class BalanceTemplateCostTest < ActiveSupport::TestCase
  setup do
    @profile = { kind: "unit", recruit_tier: "line", models: 14, model_health: 1,
      width: 4, initiative: 3, weapon_type: "slash", melee: 1, ranged: 0, spell: 0, skill: 3, attacks: 1,
      movement: 3, morale: 5, armor_type: "medium", abilities: [],
      shooting_range: 0, shooting_template: "single" }
    @reference_profiles = %w[light medium heavy magic machine].map { |armor| @profile.merge(armor_type: armor) }
  end

  test "seed preprocessing preserves manual costs and resolves missing costs" do
    # Execute only the declarations and preprocessing, never the database writes.
    source = Rails.root.join("db/seeds.rb").read.split("\nupgrades =", 2).first
    templates = seed_templates(source)
    assert templates.all? { |row| row[:cost].positive? }
    assert_equal 55, templates.find { |row| row[:template_key] == "goblin_archers" }[:cost]
    assert_equal 200, templates.find { |row| row[:template_key] == "halberdiers" }[:cost]
    [ nil, 0, 1, 49, 50, 55, 225 ].each do |cost|
      variant = source.sub("cost: nil,", "cost: #{cost.inspect},")
      rows = seed_templates(variant)
      expected = cost.nil? || cost == 0 ? templates.first[:cost] : cost
      assert_equal expected, rows.first[:cost]
    end
  end

  test "combat effects matter while rarity and markers have no surcharge" do
    base = price
    assert_equal base, price(recruit_tier: "rare")
    assert_equal base, price(abilities: %w[monster wizardAura])
    assert_operator price(abilities: [ "supportRank" ]), :>, base
    assert_operator price(abilities: [ "runeArmor", "dodge" ]), :>, base
    assert_operator price(models: 28), :>, base
    assert_operator price(attacks: 3), :>, base
    assert_operator price(morale: 9, models: 28), :>, price(models: 28)
    assert_operator price(movement: 20, abilities: [ "flying" ]), :>, base
    assert_equal price(models: 1, width: 1), price(models: 1, width: 1, abilities: [ "supportRank" ])
  end

  test "shooting uses missile attacks range and area" do
    ranged = @profile.merge(ranged: 3, shooting_range: 9, shooting_template: "single")
    base = Balance::TemplateCost.compute(ranged, reference_profiles: @reference_profiles)
    [ { missile_attacks: 3 }, { shooting_range: 16 }, { shooting_template: "blast" } ].each do |change|
      variant = ranged.merge(change)
      assert_operator Balance::TemplateCost.shooting_power(variant, [], 4, reference_profiles: @reference_profiles),
        :>, Balance::TemplateCost.shooting_power(ranged, [], 4, reference_profiles: @reference_profiles)
      assert_operator Balance::TemplateCost.compute(variant, reference_profiles: @reference_profiles), :>=, base
    end
  end

  test "strong profiles do not collapse onto the old 400 cap" do
    assert_operator price(models: 20, model_health: 6, melee: 6, attacks: 4), :>, 400
  end

  test "weak shooting is priced after rounding and not as fractional damage" do
    weak = @profile.merge(weapon_type: "ranged", ranged: 1)
    strong = weak.merge(ranged: 2)
    weak_power = Balance::TemplateCost.effective_power(weak, "shooting", reference_profiles: @reference_profiles)
    strong_power = Balance::TemplateCost.effective_power(strong, "shooting", reference_profiles: @reference_profiles)
    assert_operator weak_power, :<, 0.3
    assert_operator strong_power, :>, weak_power * 4
  end

  test "piercing is not a universal damage bonus at rounding thresholds" do
    attacker = @profile.merge(weapon_type: "slash", melee: 1)
    defender = { armor_type: "medium", abilities: [] }
    ordinary = Balance::TemplateCost.sample_damage(attacker, defender, "melee")
    piercing = Balance::TemplateCost.sample_damage(attacker.merge(abilities: [ "armorPiercing" ]), defender, "melee")
    assert_operator ordinary, :>, piercing
  end

  test "rune armor and skirmishing mitigate damage before rounding" do
    @reference_profiles = @reference_profiles.map { |profile| profile.merge(melee: 4) }
    base = Balance::TemplateCost.incoming_factor(@profile, reference_profiles: @reference_profiles)
    %w[runeArmor skirmisher shieldwall].each do |rule|
      assert_operator Balance::TemplateCost.incoming_factor(@profile.merge(abilities: [ rule ]), reference_profiles: @reference_profiles), :<, base
    end
  end

  test "flight improves firing angles as well as movement" do
    shooter = @profile.merge(weapon_type: "ranged", ranged: 1)
    assert_operator Balance::TemplateCost.effective_power(shooter.merge(abilities: [ "flying" ]), "shooting", reference_profiles: @reference_profiles),
      :>, Balance::TemplateCost.effective_power(shooter, "shooting", reference_profiles: @reference_profiles)
  end

  test "editing the engine weapon armor coefficient changes price without pricing edits" do
    attacker = @profile.merge(armor_type: "heavy", melee: 4)
    targets = [ @profile.merge(weapon_type: "puncture") ]
    before = Balance::TemplateCost.compute(attacker, reference_profiles: targets)
    table = Sim::Constants::WEAPON_VS_ARMOR.deep_dup
    table["medium"]["slash"] = 4.0
    with_combat_table(table) do
      assert_operator Balance::TemplateCost.compute(attacker, reference_profiles: targets), :>, before
    end
  end

  test "new weapon and armor types work through seed profiles and engine table" do
    attacker = @profile.merge(weapon_type: "acid", melee: 4)
    target = @profile.merge(armor_type: "crystal")
    table = Sim::Constants::WEAPON_VS_ARMOR.deep_dup
    table["crystal"] = { "acid" => 0.25 }
    with_combat_table(table) do
      weak = Balance::TemplateCost.effective_power(attacker, "melee", reference_profiles: [ target ])
      table["crystal"]["acid"] = 3.0
      assert_operator Balance::TemplateCost.effective_power(attacker, "melee", reference_profiles: [ target ]), :>, weak
      assert Balance::TemplateCost.compute(target, reference_profiles: [ attacker ]).positive?
    end
  end

  test "reference stats change defense estimates but prices and ordering do not" do
    defender = @profile.merge(armor_type: "heavy")
    weak = Balance::TemplateCost.incoming_factor(defender, reference_profiles: [ @profile ])
    strong = Balance::TemplateCost.incoming_factor(defender, reference_profiles: [ @profile.merge(melee: 6) ])
    assert_not_equal weak, strong
    before = price
    @reference_profiles = @reference_profiles.reverse.map { |profile| profile.merge(cost: 9999) }
    assert_equal before, price
  end

  test "seed population is normalized before pricing and independent of order" do
    source = Rails.root.join("db/seeds.rb").read.split("\nupgrades =", 2).first
    original = seed_templates(source)
    reversed = seed_templates(source.sub("reference_profiles = templates.map", "reference_profiles = templates.reverse.map"))
    assert_equal original.to_h { |row| [ row[:template_key], row[:cost] ] },
      reversed.to_h { |row| [ row[:template_key], row[:cost] ] }
    assert original.all? { |row| row[:model_class].present? && row[:movement].positive? }
  end

  test "empty population is rejected and harmless population stays finite" do
    assert_raises(ArgumentError) { Balance::TemplateCost.compute(@profile, reference_profiles: []) }
    harmless = @profile.merge(melee: 0, ranged: 0, spell: 0)
    assert_equal 1.0, Balance::TemplateCost.incoming_factor(@profile, reference_profiles: [ harmless ])
    assert Balance::TemplateCost.compute(@profile, reference_profiles: [ harmless ]).positive?
  end

  private

  def with_combat_table(table)
    original = Sim::Constants::WEAPON_VS_ARMOR
    Sim::Constants.send(:remove_const, :WEAPON_VS_ARMOR)
    Sim::Constants.const_set(:WEAPON_VS_ARMOR, table)
    yield
  ensure
    Sim::Constants.send(:remove_const, :WEAPON_VS_ARMOR)
    Sim::Constants.const_set(:WEAPON_VS_ARMOR, original)
  end

  def seed_templates(source)
    Object.new.instance_eval(source + "\ntemplates", "db/seeds.rb")
  end

  def price(**changes)
    Balance::TemplateCost.compute(@profile.merge(changes), reference_profiles: @reference_profiles)
  end
end
