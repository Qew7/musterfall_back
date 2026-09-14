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

  test "keeps preferred width and fills the front rank first" do
    [
      [ 10, 5, 2 ],
      [ 8, 5, 2 ],
      [ 4, 4, 1 ]
    ].each do |models, files, ranks|
      metrics = Sim::Geometry::Formation.metrics(
        models_remaining: models,
        frontage: 5,
        max_files: 5,
        model_width: 1,
        model_depth: 1
      )

      assert_equal files, metrics[:files], "models=#{models}"
      assert_equal ranks, metrics[:ranks], "models=#{models}"
    end
  end
end
