require "mkmf"

dir_config("sim_obb")
$CFLAGS << " -O3 -ffast-math -std=c99"
create_makefile("sim_obb")
