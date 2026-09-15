require "sim_test_helper"
require "open3"
require "rbconfig"

class SimObbNativeParityTest < SimTestCase
  test "Ruby and native collision queries agree in independent processes" do
    skip "compile the OBB extension to run parity checks" unless Sim::Geometry::Obb.native?

    modes = %w[ruby native].to_h do |mode|
      output, error, status = Open3.capture3(
        { "SIM_OBB_MODE" => mode }, RbConfig.ruby, "-EUTF-8",
        File.join(SimTools::ROOT, "test/support/obb_parity_queries.rb")
      )
      assert status.success?, "#{mode} query process failed: #{error}"
      [ mode, JSON.parse(output) ]
    end
    assert_equal false, modes["ruby"]["native"]
    assert_equal true, modes["native"]["native"]
    modes["ruby"]["queries"].each_with_index do |query, index|
      assert_equal query, modes["native"]["queries"][index], "geometry query seed=812 sample=#{index}"
    end
  end
end
