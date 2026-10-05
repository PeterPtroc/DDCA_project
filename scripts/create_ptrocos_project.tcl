# Independent board project. The frozen CPU/project/constraints are read only.
set script_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $script_dir ..]]
cd $root
set firmware [file join $root build hex ptrocos_ddr2.hex]
if {![file isfile $firmware] || [file size $firmware]==0} {
    error "Build scripts/build_ptrocos.ps1 before creating the board project"
}
set_msg_config -id {Synth 8-4445} -new_severity ERROR
set out [file join $root build ptrocos_vivado]
file mkdir $out
create_project ptrocos $out -part xc7a100tcsg324-1 -force
set source_file [open [file join $script_dir ptrocos_sources.txt] r]
foreach relative [split [string trim [read $source_file]] \n] {
    add_files -norecurse [file join $root [string trim $relative]]
}
close $source_file
add_files -norecurse [file join $root src rtl top ptrocos_nexys_a7_top.v]
add_files -fileset constrs_1 -norecurse [file join $root constraints nexys_a7_100t.xdc]
add_files -fileset constrs_1 -norecurse [file join $root constraints ptrocos_cdc.xdc]
set_property PROCESSING_ORDER LATE [get_files ptrocos_cdc.xdc]
set_property USED_IN_SYNTHESIS false [get_files ptrocos_cdc.xdc]
set_property top ptrocos_nexys_a7_top [current_fileset]
set_property generic [list "IMEM_HEX=$firmware" "CPU_PC_NEXT_STYLE=0"] [current_fileset]
create_ip -name mig_7series -vendor xilinx.com -library ip -version 4.2 -module_name ptrocos_ddr2_mig
source [file join $script_dir configure_ptrocos_mig.tcl]
# Global synthesis sees the actual feedback reference clock from the MIG MMCM.
set_property GENERATE_SYNTH_CHECKPOINT false [get_files ptrocos_ddr2_mig.xci]
add_files -fileset utils_1 -norecurse [list [file join $script_dir finalize_ptrocos_timing.tcl] [file join $script_dir check_routed_timing.tcl]]
foreach run [get_runs {synth_1 impl_1}] {
    set_property AUTO_INCREMENTAL_CHECKPOINT 0 $run
    set_property INCREMENTAL_CHECKPOINT {} $run
}
set impl [get_runs impl_1]
set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE ExtraPostPlacementOpt $impl
set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true $impl
set_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore $impl
set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE AggressiveExplore $impl
set_property STEPS.ROUTE_DESIGN.TCL.POST [file join $script_dir finalize_ptrocos_timing.tcl] $impl
set_property STEPS.WRITE_BITSTREAM.TCL.PRE [file join $script_dir check_routed_timing.tcl] $impl
puts "PTROCOS PROJECT CREATED: $out"
