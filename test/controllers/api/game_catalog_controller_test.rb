require "test_helper"

class Api::GameCatalogControllerTest < ActionDispatch::IntegrationTest
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
  end
end
