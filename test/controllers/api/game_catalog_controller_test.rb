require "test_helper"

class Api::GameCatalogControllerTest < ActionDispatch::IntegrationTest
  test "returns seeded game catalog" do
    get "/api/game_catalog"

    assert_response :success

    payload = response.parsed_body
    assert_kind_of Array, payload["factions"]
    assert_kind_of Array, payload["units"]
    assert_kind_of Array, payload["heroes"]
    assert_kind_of Array, payload["abilities"]
    assert_kind_of Array, payload["hero_upgrades"]
  end
end
