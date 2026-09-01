require "test_helper"

class SimCampaignChaosSpawnTest < ActiveSupport::TestCase
  ChaosSpawn = Sim::Campaign::RecruitRules::ChaosSpawn

  test "mutation_count is treasury divided by 200 rounded up" do
    assert_equal 0, ChaosSpawn.mutation_count(0)
    assert_equal 1, ChaosSpawn.mutation_count(100)
    assert_equal 1, ChaosSpawn.mutation_count(200)
    assert_equal 2, ChaosSpawn.mutation_count(201)
    assert_equal 3, ChaosSpawn.mutation_count(600)
  end

  test "apply! does not repeat ability mutations" do
    load Rails.root.join("db/seeds.rb")
    Sim::Catalog::Loader.reset!
    catalog = Sim::Catalog::Loader.load
    factory = Sim::Entities::Factory.new(catalog, id_sequence: { value: 0 })
    entity = factory.create_unit("rift_mutant", "test")

    ChaosSpawn.apply!(entity, 600, Sim::Rng::Seeded.new(42))

    assert_equal entity.dig(:components, :abilities).uniq.length, entity.dig(:components, :abilities).length
    assert_equal 600, entity.dig(:components, :economy, :cost)
  end

  test "balance duels apply simulation treasury to rift mutant" do
    load Rails.root.join("db/seeds.rb")
    Sim::Catalog::Loader.reset!
    catalog = Sim::Catalog::Loader.load
    left, = Balance::Synthetic::Duel.build_players(
      catalog,
      { left_template: "rift_mutant", right_template: "orc_brutes" },
      contact: "front",
      deploy: "ranged"
    )

    entity = left[:roster].first
    assert_equal 600, entity.dig(:components, :economy, :cost)
    assert_operator entity.dig(:components, :abilities).length, :>, 1
  end
end
