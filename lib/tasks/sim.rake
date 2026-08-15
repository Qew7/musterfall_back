namespace :sim do
  desc "Compile the OBB C kernel used by pathing"
  task :compile_obb do
    dir = File.expand_path("../../ext/sim_obb", __dir__)
    Dir.chdir(dir) do
      sh "ruby extconf.rb"
      sh "make"
    end
    puts "Compiled #{dir}/sim_obb.so" if File.exist?(File.join(dir, "sim_obb.so"))
  end
end
