require "test_helper"

class SimEntitiesFootprintTest < ActiveSupport::TestCase
  test "hero draft +1 HP keeps one model footprint" do
    hero = {
      kind: "hero",
      state: { current_health: 5 },
      components: {
        health: { model_health: 4, max: 5 },
        formation: {
          models: 1,
          frontage: 1,
          max_files: 5,
          model_class: "infantry",
          model_width: 1,
          model_depth: 1
        }
      }
    }

    Sim::Entities::Footprint.sync_entity!(hero)

    assert_equal 1, hero.dig(:components, :formation, :files)
    assert_equal 1, hero.dig(:components, :formation, :ranks)
    assert_equal 1, hero.dig(:components, :formation, :width)
    assert_equal 1, hero.dig(:components, :formation, :depth)
  end
end
