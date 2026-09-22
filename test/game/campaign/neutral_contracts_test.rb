require "test_helper"

class SimNeutralContractsTest < ActiveSupport::TestCase
  Battle = Sim::Battle

  setup do
    Sim::Catalog::Loader.reset!
    @catalog = Sim::Catalog::Loader.load
    @factory = Sim::Entities::Factory.new(@catalog, id_sequence: { value: 0 })
  end

  test "neutral roster has all thirteen selected contracts and the intended tiers" do
    assert @catalog.faction("mercenaries")[:neutral]
    units = @catalog.unit_templates("mercenaries")
    assert_equal({ "line" => 3, "elite" => 5, "rare" => 5 }, units.group_by { |entry| entry[:recruit_tier] }.transform_values(&:size))
    assert_equal [ "unpaidTab" ], @catalog.template("unpaid_company")[:abilities]
    assert_equal [ "holdMarket" ], @catalog.template("mercenary_ogres")[:abilities]
    assert_equal 14, @catalog.template("free_fencers")[:models] * @catalog.template("free_fencers")[:model_health]
    assert_equal [ "forfeitBounty" ], @catalog.template("free_fencers")[:abilities]
    assert_empty @catalog.hero_templates("mercenaries")
    units.each { |template| template[:abilities].each { |key| assert @catalog.ability(key), key } }
  end

  test "forfeit bounty gives full unit points immediately and never doubles on death" do
    unit = BattleScenarios.combatant(cost: 175, unit_cost: 175, abilities: [ "forfeitBounty" ])
    assert_equal 175, Battle::State.unit_bounty(unit)
    unit[:models_remaining] = 4
    assert_equal 175, Battle::State.unit_bounty(unit)
    unit[:current_health] = 0
    assert_equal 175, Battle::State.unit_bounty(unit)
    assert_equal 175, Battle::State.snapshot_combatant(unit)[:victory_points]
  end

  test "attached hero costs are not forfeited until ordinary casualty conditions" do
    unit = BattleScenarios.combatant(cost: 275, unit_cost: 175, abilities: [ "forfeitBounty" ])
    assert_equal 175, Battle::State.unit_bounty(unit)
    unit[:models_remaining] = 4
    assert_equal 225, Battle::State.unit_bounty(unit)
    unit[:is_routing] = true
    assert_equal 275, Battle::State.unit_bounty(unit)
  end

  test "only deployed fencers award bounty and setup logs are persisted in the replay" do
    fighter = entity("free_fencers")
    owner = player([ fighter ])
    assert_empty Battle::State.build_side(owner, "left", 0)[:combatants]
    deploy(fighter)
    side = Battle::State.build_side(owner, "left", 0)
    assert_equal 175, Battle::State.victory_points(side)
    assert side[:setup_actions].first[:details].any?
    enemy = entity("state_swords", owner: "player-2")
    deploy(enemy)
    report = Battle::Simulator.call(owner, player([ enemy ], id: "player-2"), @catalog, rng: Sim::Rng::Seeded.new(87), terrain: [])
    assert_equal "Условия найма", report[:rounds].first[:turns].first[:phases].first[:label]
    assert_equal 175, report[:initial_snapshot].find { |entry| entry[:entity_id] == fighter[:id] }[:victory_points]
    game = create_active_game
    saved = Sim::Persistence::BattleWriter.persist!(game, report, round_number: 1)
    assert saved.battle_rounds.joins(battle_turns: :battle_phases).where(battle_phases: { label: "Условия найма" }).exists?
  end

  test "treasury thresholds use the final allowance and affect unit attack contributors only for this battle" do
    guard = entity("treasury_guard")
    deploy(guard)
    original = Marshal.load(Marshal.dump(guard[:components]))
    { 0 => 0, 199 => 0, 200 => 1, 399 => 1, 400 => 2, 2000 => 2 }.each do |money, bonus|
      side = Battle::State.build_side(player([ guard ], treasury: money), "left", 0)
      unit = side[:combatants].first
      assert_equal original[:combat][:melee] + bonus, unit[:melee]
      assert_equal original[:combat][:morale] + bonus, unit[:morale]
      assert_equal original[:combat][:melee] + bonus, unit[:contributors][:melee].first[:power]
      assert_equal money, unit[:treasury_at_start]
      assert_equal original, guard[:components]
    end
  end

  test "income is fixed from the reserve at battle start and ignores dead or deployed companies" do
    reserve = entity("caravan_company")
    deployed = entity("caravan_company")
    dead = entity("caravan_company")
    dead[:state][:current_health] = 0
    deploy(deployed)
    owner = player([ reserve, deployed, dead ])
    side = Battle::State.build_side(owner, "left", 0)
    assert_equal [ reserve[:id] ], side[:campaign_rewards].map { |entry| entry[:entity_id] }
    reserve[:components][:formation][:row] = "front"
    rewards = Battle::Rules.for(:campaign).income_rewards(side)
    assert_equal [ 200 ], rewards.map { |entry| entry[:amount] }
  end

  test "each reserve contract augments the next allowance after its reset with no carry over" do
    campaign = Sim::Campaign::Create.call(player_count: 2).value
    owner = campaign.find_player("player-1")
    owner[:treasury] = 899
    reserves = [ entity("caravan_company"), entity("caravan_company") ]
    owner[:roster] = reserves
    side = Battle::State.build_side(owner, "left", 0)
    reward_side = Battle::State.snapshot_side(owner, side, @catalog)
    # A report is marshalled to JSON before asynchronous settlement.
    reward_side = JSON.parse(reward_side.to_json)
    reward_side["campaign_rewards"] << reward_side["campaign_rewards"].first.dup
    battle = { left: reward_side, right: { player_id: "player-2", combatants: [] }, winner_id: "player-1" }
    settled = Sim::Campaign::SettleMatchups.call(campaign: campaign, battles: [ battle ]).value[:campaign]
    assert_equal Sim::Constants.income_for(2) + 400, settled.find_player("player-1")[:treasury]
    assert_equal Sim::Constants.income_for(2), settled.find_player("player-2")[:treasury]
    assert_equal 2, settled.find_player("player-1")[:round_notes].count { |note| note.include?("работа в резерве") }
    assert_equal 899, owner[:treasury]
  end

  test "free passes do not earn reserve income" do
    campaign = Sim::Campaign::Create.call(player_count: 2).value
    campaign.find_player("player-1")[:roster] = [ entity("caravan_company") ]
    result = Sim::Campaign::SettleMatchups.call(campaign: campaign, battles: [], byes: [ { player_id: "player-1" } ])
    assert_equal Sim::Constants.income_for(2), result.value[:campaign].find_player("player-1")[:treasury]
  end

  test "automatic deployment keeps productive reserves only with an existing field force" do
    reserve = entity("caravan_company")
    roster = [ reserve, entity("state_swords"), entity("state_swords") ]
    Sim::Geometry::Deployment.pack_roster!(roster)
    assert_equal "reserve", reserve.dig(:components, :formation, :row)
    roster.drop(1).each do |unit|
      refute_equal "reserve", unit.dig(:components, :formation, :row)
      assert_nil Sim::Geometry::Deployment.clash_reason(unit, unit[:components][:formation], roster)
    end
    Sim::Geometry::Deployment.pack_roster!([ reserve ])
    refute_equal "reserve", reserve.dig(:components, :formation, :row)
  end

  test "bot shopping preserves a useful treasury threshold by a discovered rule hook" do
    campaign = Sim::Campaign::Create.call(player_count: 2).value
    owner = campaign.find_player("player-1")
    owner.merge!(faction_id: "empire", treasury: 550, recruit_access: 3, recruit_strategy: "horde")
    owner[:roster] = [ entity("treasury_guard"), entity("state_swords"), entity("state_swords") ]
    Sim::Campaign::BotRecruit.call(campaign: campaign, catalog: @catalog, player_id: owner[:id], rng: Sim::Rng::Seeded.new(55), allow_access_upgrades: false)
    assert_operator owner[:treasury], :>=, 400
    assert_operator owner[:treasury], :<, 550
    assert_equal 400, Sim::ArmyComposition.treasury_reserve(owner[:roster], owner[:treasury])
    assert_equal 0, Sim::ArmyComposition.treasury_reserve([ entity("state_swords") ], 550)
  end

  private

  def entity(key, owner: "player-1")
    @factory.create_unit(key, owner)
  end

  def player(roster, id: "player-1", treasury: 0)
    { id: id, name: id, faction_id: "empire", roster: roster, treasury: treasury }
  end

  def deploy(unit)
    unit[:components][:formation].merge!(Sim::Geometry::Battlefield.default_deployment("front", "center"), row: "front")
  end
end
