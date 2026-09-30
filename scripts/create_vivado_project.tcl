# Vivado batch project bootstrap. Run from the repository root:
#   vivado -mode batch -source scripts/create_vivado_project.tcl
set script_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $script_dir ..]]
cd $root
set build_dir [file join $root build vivado]
file mkdir $build_dir
create_project rv32_digital_analyzer $build_dir -part xc7a100tcsg324-1 -force
foreach rtl_dir {bus cpu memory peripheral top} {
    add_files -norecurse [glob -directory [file join $root src rtl $rtl_dir] -types f *.v]
}
add_files -fileset constrs_1 -norecurse [file join $root constraints nexys_a7_100t.xdc]
set_property top nexys_a7_top [current_fileset]
update_compile_order -fileset sources_1
puts "Vivado project created at $build_dir"
