require "test_helper"

class SimGeometryFormationTest < ActiveSupport::TestCase
  test "zero models yields empty footprint" do
    metrics = Sim::Geometry::Formation.metrics(
      models_remaining: 0,
      frontage: 5,
      max_files: 5,
      model_width: 1,
      model_depth: 1
    )

    assert_equal 0, metrics[:files]
    assert_equal 0, metrics[:ranks]
  end

  test "caps files by frontage and max files" do
    metrics = Sim::Geometry::Formation.metrics(
      models_remaining: 12,
      frontage: 4,
      max_files: 5,
      model_width: 1,
      model_depth: 1
    )

    assert_equal 4, metrics[:files]
    assert_equal 3, metrics[:ranks]
    assert_equal 4, metrics[:footprint_width]
    assert_equal 3, metrics[:footprint_depth]
  end
end
