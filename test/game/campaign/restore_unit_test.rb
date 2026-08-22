require "test_helper"

class SimCampaignRestoreUnitTest < ActiveSupport::TestCase
  setup do
    @game = create_active_game
    assign_first_faction!(@game)
    @campaign = Sim::Persistence::CampaignRepository.new.load(@game.reload)
    @player = @campaign.find_player("player-1")
    @template = catalog.unit_templates(@player[:faction_id])
      .select { |template| template[:recruit_tier] == "line" && template[:models] > 1 }
      .min_by { |template| template[:cost] }

    result = Sim::Campaign::Recruit.call(
      campaign: @campaign,
      catalog: catalog,
      player_id: @player[:id],
      template_id: @template[:id]
    )
    assert result.ok?, result.error
    @campaign = result.value
    @player = @campaign.find_player("player-1")
    @entity = @player[:roster].find { |entry| entry[:template_id] == @template[:id] }
  end

  test "restores as many models as treasury allows" do
    model_health = @entity.dig(:components, :health, :model_health)
    max_models = @entity.dig(:components, :formation, :models)
    @entity[:state][:current_health] = model_health * (max_models - 5)
    per = (@template[:cost].to_f / @template[:models]).ceil
    @player[:treasury] = per * 2

    result = Sim::Campaign::RestoreUnit.call(
      campaign: @campaign,
      catalog: catalog,
      player_id: @player[:id],
      entity_id: @entity[:id]
    )

    assert result.ok?, result.error
    player = result.value.find_player(@player[:id])
    entity = player[:roster].find { |entry| entry[:id] == @entity[:id] }
    assert_equal 0, player[:treasury]
    assert_equal (max_models - 3) * model_health, entity.dig(:state, :current_health)
  end

  test "fails when treasury cannot buy a single model" do
    model_health = @entity.dig(:components, :health, :model_health)
    max_models = @entity.dig(:components, :formation, :models)
    @entity[:state][:current_health] = model_health * (max_models - 2)
    @player[:treasury] = 0

    result = Sim::Campaign::RestoreUnit.call(
      campaign: @campaign,
      catalog: catalog,
      player_id: @player[:id],
      entity_id: @entity[:id]
    )

    assert result.failure?
    assert_equal "insufficient treasury", result.error
  end
end
