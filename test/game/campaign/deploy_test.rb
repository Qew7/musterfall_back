require "test_helper"

class SimCampaignDeployTest < ActiveSupport::TestCase
  setup do
    @game = create_active_game
    assign_first_faction!(@game)
    @campaign = Sim::Persistence::CampaignRepository.new.load(@game.reload)
    @hero_id = @campaign.find_player("player-1")[:roster].first[:id]
    player = @campaign.find_player("player-1")
    @template = catalog.unit_templates(player[:faction_id])
      .select { |template| template[:recruit_tier] == "line" }
      .min_by { |template| template[:cost] }
  end

  def recruit_commons!(count)
    player = @campaign.find_player("player-1")
    player[:treasury] = [ player[:treasury], @template[:cost] * count ].max
    count.times do
      result = Sim::Campaign::Recruit.call(
        campaign: @campaign,
        catalog: catalog,
        player_id: "player-1",
        template_id: @template[:id]
      )
      raise result.error unless result.ok?

      @campaign = result.value
    end
  end

  test "auto deploy places living entities out of reserve" do
    result = Sim::Campaign::Deploy.call(campaign: @campaign, player_id: "player-1", action: "auto")
    assert result.ok?
    hero = result.value.find_entity("player-1", @hero_id)
    assert_not_equal "reserve", hero.dig(:components, :formation, :row)
  end

  test "transform rejects attached hero placement" do
    recruit_commons!(1)
    unit_id = @campaign.find_player("player-1")[:roster].find { |entity| entity[:kind] == "unit" }[:id]
    @campaign = Sim::Campaign::AttachHero.call(
      campaign: @campaign,
      player_id: "player-1",
      hero_id: @hero_id,
      unit_id: unit_id
    ).value

    result = Sim::Campaign::Deploy.call(
      campaign: @campaign,
      player_id: "player-1",
      action: "transform",
      entity_id: @hero_id,
      x: 3,
      y: 10
    )

    assert result.failure?
  end

  test "unknown action fails" do
    result = Sim::Campaign::Deploy.call(campaign: @campaign, player_id: "player-1", action: "teleport")
    assert result.failure?
  end

  test "transform rejects footprints packed inside melee contact" do
    recruit_commons!(2)

    units = @campaign.find_player("player-1")[:roster].select { |entity| entity[:kind] == "unit" }
    first, second = units.first(2)
    @campaign = Sim::Campaign::Deploy.call(
      campaign: @campaign,
      player_id: "player-1",
      action: "transform",
      entity_id: first[:id],
      x: 8,
      y: 12,
      facing: 0
    ).value

    result = Sim::Campaign::Deploy.call(
      campaign: @campaign,
      player_id: "player-1",
      action: "transform",
      entity_id: second[:id],
      x: 8,
      y: 12,
      facing: 0
    )

    assert result.failure?
    assert_match(/слишком близко/, result.error)
  end

  test "auto deploy keeps living footprints outside melee contact" do
    recruit_commons!(4)

    result = Sim::Campaign::Deploy.call(campaign: @campaign, player_id: "player-1", action: "auto")
    assert result.ok?

    player = result.value.find_player("player-1")
    footprints = player[:roster]
      .select { |entity| entity.dig(:state, :current_health).to_i > 0 }
      .reject { |entity| entity[:kind] == "hero" && entity[:state][:attached_to] }
      .reject { |entity| entity.dig(:components, :formation, :row) == "reserve" }
      .map { |entity| Sim::Geometry::Deployment.footprint_from_entity(entity) }

    footprints.combination(2).each do |left, right|
      refute Sim::Geometry::Deployment.too_close?(left, right),
        "#{left[:name]} @#{left[:x]},#{left[:y]} too close to #{right[:name]} @#{right[:x]},#{right[:y]}"
    end

    player[:roster]
      .select { |entity| entity.dig(:state, :current_health).to_i > 0 }
      .reject { |entity| entity[:kind] == "hero" && entity[:state][:attached_to] }
      .reject { |entity| entity.dig(:components, :formation, :row) == "reserve" }
      .each do |entity|
        clash = Sim::Geometry::Deployment.clash_reason(
          entity, entity[:components][:formation], player[:roster], ignore_id: entity[:id]
        )
        assert_nil clash, "#{entity[:name]} would be rejected as a player transform: #{clash}"
      end
  end

  test "auto deploy keeps 4x4 trays inside the deployment zone on both sides" do
    roster = 6.times.map { |index| block_entity("swords-#{index}", y: index.even? ? 0 : 23) }

    Sim::Geometry::Deployment.pack_roster!(roster)

    fielded = roster.reject { |entity| entity.dig(:components, :formation, :row) == "reserve" }
    assert_equal 6, fielded.length
    fielded.each do |entity|
      formation = entity[:components][:formation]
      assert_nil Sim::Geometry::Deployment.clash_reason(entity, formation, roster, ignore_id: entity[:id]),
        "#{entity[:name]} @#{formation[:x]},#{formation[:y]} would be rejected as a player transform"
      [ 0, 1 ].each do |side|
        pose = Sim::Geometry::Battlefield.battle_position(formation, side)
        tray = Sim::Geometry::Deployment.footprint_from_entity(entity, x: pose[:x], y: pose[:y], facing: pose[:facing])
        assert Sim::Geometry::Battlefield.tray_on_battlefield?(tray),
          "#{entity[:name]} side #{side} hangs off the field at #{pose[:x]},#{pose[:y]}"
      end
    end
  end

  test "transform rejects a 4x4 tray hanging off the field edge" do
    recruit_commons!(1)
    unit = @campaign.find_player("player-1")[:roster].find { |entity| entity[:kind] == "unit" }
    make_block!(unit)

    result = Sim::Campaign::Deploy.call(
      campaign: @campaign,
      player_id: "player-1",
      action: "transform",
      entity_id: unit[:id],
      x: 8,
      y: 0,
      facing: 0
    )

    assert result.failure?
    assert_match(/не помещается/, result.error)
  end

  private

  def block_entity(id, y:)
    {
      id: id,
      name: id,
      kind: "unit",
      state: { current_health: 16 },
      components: {
        health: { max: 16, model_health: 1 },
        formation: {
          x: 8,
          y: y,
          facing: 0,
          row: "front",
          lane: "center",
          models: 16,
          frontage: 4,
          max_files: 4,
          model_width: 1.0,
          model_depth: 1.0,
          files: 4,
          ranks: 4,
          width: 4.0,
          depth: 4.0
        }
      }
    }
  end

  def make_block!(entity)
    formation = entity[:components][:formation]
    formation[:frontage] = 4
    formation[:max_files] = 4
    formation[:models] = 16
    formation[:model_width] = 1.0
    formation[:model_depth] = 1.0
    entity[:state][:current_health] = 16
    entity[:components][:health][:max] = 16
    entity[:components][:health][:model_health] = 1
    Sim::Entities::Footprint.sync_entity!(entity)
  end
end
