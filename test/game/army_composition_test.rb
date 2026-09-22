require "test_helper"

class SimArmyCompositionTest < ActiveSupport::TestCase
  setup do
    @catalog = Sim::Catalog::Loader.load
    @factory = Sim::Entities::Factory.new(@catalog, id_sequence: { value: 0 })
  end

  test "rules prioritize a missing partner and reduce surplus copies without faction checks" do
    gun = @factory.create_unit("sling_catapult", "p")
    supplier = @catalog.template("goblin_archers").merge(id: "arbitrary_provider", faction_id: "anything")
    before = weight(supplier, [ gun ])
    goblin = @factory.create_unit("goblin_archers", "p")
    after = weight(supplier, [ gun, goblin ])
    assert_operator before, :>, after
    duplicate = supplier.merge(id: "goblin_archers")
    assert_operator weight(duplicate, [ gun, goblin ]), :<, after
  end

  test "unaffordable partners do not attract extra consumers" do
    template = @catalog.template("sling_catapult")
    fodder = @catalog.template("goblin_archers")
    options = [ template, fodder ]
    full = Sim::ArmyComposition.recruit_weight(template, roster: [], options: options, treasury: template[:cost] + fodder[:cost])
    short = Sim::ArmyComposition.recruit_weight(template, roster: [], options: options, treasury: template[:cost])
    assert_operator full, :>, short
  end

  test "supply demand follows actual remaining models rather than a fixed unit ratio" do
    guns = 2.times.map { @factory.create_unit("sling_catapult", "p") }
    goblin = @factory.create_unit("goblin_archers", "p")
    template = @catalog.template("goblin_archers")
    sufficient = weight(template, guns + [ goblin ])
    goblin[:state][:current_health] = 1
    insufficient = weight(template, guns + [ goblin ])
    assert_operator insufficient, :>, sufficient
  end

  test "a newly registered rule drives bot packing and placement without bot edits" do
    link = Sim::ArmySynergy.new(
      consumer: ->(profile) { Array(profile[:abilities]).include?("newConsumer") },
      provider: ->(profile) { Array(profile[:abilities]).include?("newProvider") },
      capacity: ->(profile) { profile[:models].to_f }, range: ->(_profile) { 4.0 }, required: true
    )
    rule = Module.new
    rule.define_singleton_method(:army_synergies) { [ link ] }
    rule.define_singleton_method(:bot_pack_as) { |profile| :supply if link.provider?(profile) }
    rules = Sim::Battle::Rules.army_rules + [ rule ]
    with_army_rules(rules) do
      consumer = @factory.create_unit("orc_brutes", "p")
      consumer[:components][:abilities] = [ "newConsumer" ]
      supplier = @factory.create_unit("goblin_archers", "p")
      supplier[:components][:abilities] = [ "newProvider" ]
      template = @catalog.template("goblin_archers").merge(abilities: [ "newProvider" ])
      assert_equal :supply, Sim::ArmyComposition.bot_pack_as(template)
      assert_operator weight(template, [ consumer ]), :>, weight(template, [ consumer, supplier ])
      roster = [ consumer, supplier ]
      Sim::Geometry::Deployment.pack_roster!(roster)
      assert_operator Sim::Geometry::Battlefield.distance_between_units(
        Sim::Geometry::Deployment.footprint_from_entity(consumer), Sim::Geometry::Deployment.footprint_from_entity(supplier)
      ), :<=, 4.0
      roster.each { |entity| refute_equal "reserve", entity.dig(:components, :formation, :row) }
    end
  end

  test "auto deployment places suppliers in range with legal nonoverlapping trays" do
    roster = %w[orc_brutes sling_catapult goblin_archers boar_riders].map { |key| @factory.create_unit(key, "p") }
    Sim::Geometry::Deployment.pack_roster!(roster)
    gun = roster.find { |e| e[:template_id] == "sling_catapult" }
    supplier = roster.find { |e| e[:template_id] == "goblin_archers" }
    trays = roster.map { |e| Sim::Geometry::Deployment.footprint_from_entity(e) }
    assert_operator Sim::Geometry::Battlefield.distance_between_units(
      Sim::Geometry::Deployment.footprint_from_entity(gun), Sim::Geometry::Deployment.footprint_from_entity(supplier)
    ), :<=, 6
    roster.each do |entity|
      refute_equal "reserve", entity.dig(:components, :formation, :row)
      assert_nil Sim::Geometry::Deployment.clash_reason(entity, entity[:components][:formation], roster, ignore_id: entity[:id])
    end
    trays.combination(2).each { |a, b| refute Sim::Geometry::Deployment.too_close?(a, b) }
  end

  test "dense ordinary army is fielded instead of wasting gaps between lanes" do
    roster = ([ "orc_brutes" ] * 4 + [ "goblin_archers" ] * 4).map { |key| @factory.create_unit(key, "p") }
    roster << @factory.create_hero("shaman", "p", free: true)
    Sim::Geometry::Deployment.pack_roster!(roster)
    fielded = roster.reject { |entity| entity.dig(:components, :formation, :row) == "reserve" }
    trays = fielded.map { |entity| Sim::Geometry::Deployment.footprint_from_entity(entity) }
    roster.each do |entity|
      refute_equal "reserve", entity.dig(:components, :formation, :row), entity[:name]
      assert_nil Sim::Geometry::Deployment.clash_reason(entity, entity[:components][:formation], roster, ignore_id: entity[:id])
    end
    trays.combination(2).each do |left, right|
      assert_operator Sim::Geometry::Battlefield.distance_between_units(left, right),
        :>=, Sim::Geometry::Deployment::MIN_SEPARATION
    end
    fielded.each do |entity|
      start = Sim::Geometry::Deployment.footprint_from_entity(entity)
      others = fielded.reject { |entry| entry[:id] == entity[:id] }.map { |entry| Sim::Geometry::Deployment.footprint_from_entity(entry) }
      world = Sim::Battle::Pathing::Obstacles.around(start, units: others)
      fwd = start.merge(x: start[:x] + 0.5)
      assert world.translation_clear?(start, start, fwd),
        "#{entity[:name]} cannot take a 0.5\" step from #{start[:x]},#{start[:y]}"
    end
  end

  private

  def with_army_rules(rules)
    singleton = Sim::Battle::Rules.singleton_class
    original = singleton.instance_method(:army_rules)
    singleton.define_method(:army_rules) { rules }
    yield
  ensure
    singleton.define_method(:army_rules, original)
  end

  def weight(template, roster)
    Sim::ArmyComposition.recruit_weight(template, roster: roster, options: [ template ], treasury: 1000)
  end
end
