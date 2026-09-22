require "test_helper"

class Api::GameCatalogControllerTest < ActionDispatch::IntegrationTest
  test "catalog exposes neutral factions while balance only offers playable factions" do
    neutral = Faction.create!(slug: "neutral_test", name: "Neutral", vibe: "Mercenaries", passive: "Shared", color: "#777777", neutral: true)
    get "/api/game_catalog"

    assert_response :success
    payload = response.parsed_body
    assert_equal true, payload.fetch("factions").find { |faction| faction["id"] == neutral.slug }.fetch("neutral")
    assert_equal false, payload.fetch("factions").find { |faction| faction["id"] == "empire" }.fetch("neutral")
    refute_includes Balance::Dashboard.faction_slugs, neutral.slug
    assert_includes Balance::Dashboard.faction_slugs, "empire"
    assert_raises(ArgumentError) { Balance::Simulation.normalize_config(faction_left: neutral.slug) }
    loaded = Sim::Catalog::Loader.new.load
    assert_equal true, loaded.faction(neutral.slug)[:neutral]
    refute_includes loaded.selectable_factions.map { |faction| faction[:id] }, neutral.slug
  end

  test "returns seeded game catalog" do
    with_spell_api(
      schools: %i[pyromancy],
      spell_keys: %i[fireball inferno],
      school: {
        key: :pyromancy,
        name: "Пиромантия",
        spells: [ { key: :fireball, name: "Огненный шар" } ]
      }
    ) do
      get "/api/game_catalog"
    end

    assert_response :success

    payload = response.parsed_body
    assert_kind_of Array, payload["factions"]
    assert_kind_of Array, payload["units"]
    assert_kind_of Array, payload["heroes"]
    assert_kind_of Array, payload["abilities"]
    assert_kind_of Array, payload["hero_upgrades"]
    assert_equal [ "pyromancy" ], payload["factions"].first.fetch("magicSchoolIds")
    assert_equal "Пиромантия", payload["magicSchools"].first.fetch("name")
    assert_equal [ "fireball", "inferno" ], payload["magicSchools"].first.fetch("spellKeys")
    assert_equal "Огненный шар", payload["magicSchools"].first.fetch("spells").first.fetch("name")
    matrix = payload.fetch("weaponVsArmor")
    used_weapons = ArmyTemplate.distinct.pluck(:weapon_type) | Sim::Upgrades::Draft.combat_type_assignments.fetch(:weapon_type)
    used_armors = ArmyTemplate.distinct.pluck(:armor_type) | Sim::Upgrades::Draft.combat_type_assignments.fetch(:armor_type)
    assert_equal used_weapons.sort, matrix.fetch("weaponTypes").sort
    assert_equal used_armors.sort, matrix.fetch("armorTypes").sort
    assert_includes matrix.fetch("weaponTypes"), "breath"
    assert_includes matrix.fetch("weaponTypes"), "demolish"
    refute_includes matrix.fetch("weaponTypes"), "fire"
    refute_includes matrix.fetch("weaponTypes"), "lightning"
    assert_equal "рубящий", matrix.fetch("weaponLabels").fetch("slash")
    assert_equal "тяжёлая", matrix.fetch("armorLabels").fetch("heavy")
    assert_equal 0.85, matrix.fetch("multipliers").fetch("heavy").fetch("slash")
  end
end
