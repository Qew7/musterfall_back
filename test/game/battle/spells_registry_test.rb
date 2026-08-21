require "test_helper"

class SimBattleSpellsRegistryTest < ActiveSupport::TestCase
  EXPECTED_ACCESS = {
    empire: %i[pyromancy celestial bestial shadow],
    greenskins: %i[warcry bestial pyromancy],
    undead: %i[necromancy shadow ruin],
    wildwood: %i[verdancy bestial celestial shadow],
    chaos: %i[ruin pyromancy shadow bestial]
  }.freeze

  test "registry exposes eight complete schools with unique spell contracts" do
    assert_equal EXPECTED_ACCESS, Sim::Battle::Spells::FACTION_ACCESS
    assert_equal EXPECTED_ACCESS.keys, Sim::Battle::Spells::FACTION_ACCESS.keys
    EXPECTED_ACCESS.each { |faction, schools| assert_equal schools, Sim::Battle::Spells.schools_for(faction) }
    assert_equal 8, Sim::Battle::Spells::REGISTRY.size

    spells = Sim::Battle::Spells::REGISTRY.flat_map do |school, entries|
      school_spells = entries.call
      assert_equal 6, school_spells.size, "#{school} must contain six spells"
      assert_equal school_spells.map(&:key), Sim::Battle::Spells.spell_keys(school)
      assert Sim::Battle::Spells.school(school).values.all?(&:present?)
      school_spells
    end

    assert_equal 48, spells.size
    assert_equal spells.size, spells.map(&:key).uniq.size

    spells.each do |spell|
      %i[key name description casting_value target_type requires_los? legal_targets score resolve!].each do |method|
        assert_respond_to spell, method
      end
      assert spell.const_defined?(:LOG, false)
      assert_same spell, Sim::Battle::Spells.fetch(spell.key)
      assert spell.key.is_a?(Symbol)
      assert spell.name.present?
      assert spell.description.present?
      assert_includes 8..13, spell.casting_value
      assert spell.target_type.is_a?(Symbol)
      assert_includes [ true, false ], spell.requires_los?
      assert Sim::Battle::Spells::CARD_COPY.key?(spell.key)
      assert_match(
        /Маг|Герой/,
        Sim::Battle::ActionResult.text_for(
          actor: { actor_role: "hero", actor_name: "Маг" },
          action: spell,
          target_label: "цель",
          outcome: "success",
          dice: [ 3, 4 ],
          spell_power: 5,
          casting_total: 12,
          casting_value: spell.casting_value
        )
      )
    end

    card = Sim::Battle::Spells.serialize_school(:pyromancy)
    assert_equal "Пиромантия", card[:name]
    assert_equal 6, card[:spells].size
    fireball = card[:spells].find { |entry| entry[:key] == "fireball" }
    assert_equal "Огненный шар", fireball[:name]
    assert_equal "вражеский отряд", fireball[:targetLabel]
    assert_equal 8, fireball[:castingValue]
  end
end
