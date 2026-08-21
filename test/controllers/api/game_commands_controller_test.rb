require "test_helper"

class ApiGameCommandsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Faction.count.positive? || load(Rails.root.join("db/seeds.rb"))
  end

  test "create returns campaign and version" do
    post "/api/games", params: { game: { player_count: 2 } }, as: :json
    assert_response :created
    body = JSON.parse(response.body)
    assert body["campaign"].present?
    assert_equal 0, body["version"]
  end

  test "assign faction happy path" do
    post "/api/games", params: { game: { player_count: 2 } }, as: :json
    game_id = JSON.parse(response.body)["id"]
    faction_id = JSON.parse(get_catalog)["factions"].first["id"]

    post "/api/games/#{game_id}/assign_faction", params: {
      base_version: 0,
      player_id: "player-1",
      faction_id: faction_id,
      school_key: starter_school_key(faction_id)
    }, as: :json

    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 1, body["version"]
    assert_equal faction_id, body["campaign"]["players"].first["factionId"]
  end

  test "version conflict returns 409 with campaign" do
    post "/api/games", params: { game: { player_count: 2 } }, as: :json
    game_id = JSON.parse(response.body)["id"]
    faction_id = JSON.parse(get_catalog)["factions"].first["id"]

    post "/api/games/#{game_id}/assign_faction", params: {
      base_version: 0,
      player_id: "player-1",
      faction_id: faction_id,
      school_key: starter_school_key(faction_id)
    }, as: :json
    assert_response :success

    post "/api/games/#{game_id}/recruit", params: {
      base_version: 0,
      player_id: "player-1",
      template_id: "whatever"
    }, as: :json

    assert_response :conflict
    body = JSON.parse(response.body)
    assert body["campaign"].present?
  end

  test "advance round returns battles" do
    post "/api/games", params: { game: { player_count: 2 } }, as: :json
    game_id = JSON.parse(response.body)["id"]

    post "/api/games/#{game_id}/advance_round", params: { base_version: 0 }, as: :json
    assert_response :success
    body = JSON.parse(response.body)
    assert body["battles"].any?
    assert body["campaign"]["winnerId"].present?
  end

  test "deploy auto and transform persist formation" do
    post "/api/games", params: { game: { player_count: 2 } }, as: :json
    game_id = JSON.parse(response.body)["id"]
    faction_id = JSON.parse(get_catalog)["factions"].first["id"]

    post "/api/games/#{game_id}/assign_faction", params: {
      base_version: 0,
      player_id: "player-1",
      faction_id: faction_id,
      school_key: starter_school_key(faction_id)
    }, as: :json
    assert_response :success
    version = JSON.parse(response.body)["version"]
    hero_id = JSON.parse(response.body)["campaign"]["players"].first["roster"].first["id"]

    post "/api/games/#{game_id}/deploy", params: {
      base_version: version,
      player_id: "player-1",
      deploy_mode: "auto"
    }, as: :json
    assert_response :success
    body = JSON.parse(response.body)
    hero = body["campaign"]["players"].first["roster"].find { |entity| entity["id"] == hero_id }
    assert_not_equal "reserve", hero["components"]["formation"]["row"]
    version = body["version"]

    post "/api/games/#{game_id}/deploy", params: {
      base_version: version,
      player_id: "player-1",
      deploy_mode: "transform",
      entity_id: hero_id,
      x: 4,
      y: 12,
      facing: 45
    }, as: :json
    assert_response :success
    hero = JSON.parse(response.body)["campaign"]["players"].first["roster"].find { |entity| entity["id"] == hero_id }
    assert_equal 4, hero["components"]["formation"]["x"]
    assert_equal 12, hero["components"]["formation"]["y"]
    assert_equal 45, hero["components"]["formation"]["facing"]
  end

  private

  def get_catalog
    get "/api/game_catalog"
    assert_response :success
    response.body
  end
end
