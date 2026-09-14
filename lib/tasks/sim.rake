namespace :sim do
  desc "Compile the OBB C kernel used by pathing"
  task :compile_obb do
    dir = File.expand_path("../../ext/sim_obb", __dir__)
    Dir.chdir(dir) do
      sh "ruby extconf.rb"
      sh "make clean"
      sh "make"
    end
    built = Dir[File.join(dir, "sim_obb.{so,bundle}")].max_by { |path| File.mtime(path) }
    puts "Compiled #{built}" if built
  end
end
