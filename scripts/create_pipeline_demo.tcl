# Standalone simulation project; no firmware toolchain, MIG or board required.
set script_dir [file dirname [file normalize [info script]]]
set root [file dirname $script_dir]
set out [file join $root build pipeline_demo]
if {[current_project -quiet] ne ""} {
    error "Open a fresh Vivado window before sourcing this script."
}
set project_file [file join $out pipeline_demo.xpr]
if {[file exists $project_file]} {
    open_project $project_file
} else {
    create_project pipeline_demo $out -part xc7a100tcsg324-1
    foreach module {alu crc16_unit decoder hazard_unit imm_gen regfile rv32m_unit rv32im_decoder rv32im_core} {
        add_files -norecurse [file join $root src rtl cpu ${module}.v]
    }
}
# Refresh the bench path when reopening projects created before the demo
# sources were grouped under src/sim/pipeline.
set old_bench [get_files -quiet [file join $root src sim tb_pipeline_demo.sv]]
if {[llength $old_bench]} {remove_files $old_bench}
set bench [file join $root src sim pipeline tb_pipeline_demo.sv]
if {![llength [get_files -quiet $bench]]} {
    add_files -fileset sim_1 -norecurse $bench
}
set_property top tb_pipeline_demo [get_filesets sim_1]
set_property xsim.elaborate.debug_level all [get_filesets sim_1]
set_property xsim.simulate.runtime 0ns [get_filesets sim_1]
update_compile_order -fileset sim_1
launch_simulation
source [file join $root src sim pipeline waves.tcl]
run all
save_wave_config [file join $out pipeline_demo.wcfg]
puts "Pipeline demo complete. Use Restart then Run For 10 ns to step one cycle."
