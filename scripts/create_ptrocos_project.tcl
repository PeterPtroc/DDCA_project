# PtrocOS board project; explicit RTL and board constraint lists.
set script_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $script_dir ..]]
cd $root
if {![info exists ptrocos_firmware]} {set ptrocos_firmware ddr2}
source [file join $script_dir build_guard.tcl]
set firmware [ddca_check_firmware $ptrocos_firmware]
set_msg_config -id {Synth 8-4445} -new_severity ERROR
if {[info exists ptrocos_project_folder]} {
    set project_folder $ptrocos_project_folder
} elseif {$ptrocos_firmware eq "ddr2"} {
    set project_folder ptrocos_vivado
} else {
    set project_folder ptrocos_${ptrocos_firmware}_vivado
}
set out [file join $root build $project_folder]
set project_file [file join $out ptrocos.xpr]
ddca_guard prepare project $project_file $ptrocos_firmware
ddca_guard begin project $project_file $ptrocos_firmware
file mkdir $out
create_project ptrocos $out -part xc7a100tcsg324-1 -force
set source_list ptrocos_sources.txt
set board_top ptrocos_nexys_a7_top
if {$ptrocos_firmware eq "elf"} {set source_list ptrocos_elf_sources.txt; set board_top ptrocos_elf_nexys_a7_top}
set source_file [open [file join $script_dir $source_list] r]
foreach relative [split [string trim [read $source_file]] \n] {
    add_files -norecurse [file join $root [string trim $relative]]
}
close $source_file
add_files -norecurse [file join $root src rtl top ${board_top}.v]
add_files -fileset constrs_1 -norecurse [file join $root constraints nexys_a7_100t.xdc]
add_files -fileset constrs_1 -norecurse [file join $root constraints ptrocos_cdc.xdc]
set_property PROCESSING_ORDER LATE [get_files ptrocos_cdc.xdc]
set_property USED_IN_SYNTHESIS false [get_files ptrocos_cdc.xdc]
add_files -fileset constrs_1 -norecurse [file join $root constraints ptrocos_video.xdc]
set_property PROCESSING_ORDER LATE [get_files ptrocos_video.xdc]
set_property USED_IN_SYNTHESIS false [get_files ptrocos_video.xdc]
add_files -fileset constrs_1 -norecurse [file join $root constraints ptrocos_sd.xdc]
set_property PROCESSING_ORDER LATE [get_files ptrocos_sd.xdc]
set_property USED_IN_SYNTHESIS false [get_files ptrocos_sd.xdc]
add_files -fileset constrs_1 -norecurse [file join $root constraints ptrocos_graphics.xdc]
set_property PROCESSING_ORDER LATE [get_files ptrocos_graphics.xdc]
set_property USED_IN_SYNTHESIS false [get_files ptrocos_graphics.xdc]
add_files -fileset constrs_1 -norecurse [file join $root constraints ptrocos_audio.xdc]
set_property PROCESSING_ORDER LATE [get_files ptrocos_audio.xdc]
set_property USED_IN_SYNTHESIS false [get_files ptrocos_audio.xdc]
set_property top $board_top [current_fileset]
set_property generic [list "IMEM_HEX=$firmware" "CPU_PC_NEXT_STYLE=0"] [current_fileset]
create_ip -name mig_7series -vendor xilinx.com -library ip -version 4.2 -module_name ptrocos_ddr2_mig
source [file join $script_dir configure_ptrocos_mig.tcl]
# Global synthesis sees the actual feedback reference clock from the MIG MMCM.
set_property GENERATE_SYNTH_CHECKPOINT false [get_files ptrocos_ddr2_mig.xci]
add_files -fileset utils_1 -norecurse [list [file join $script_dir prepare_ptrocos_timing.tcl] [file join $script_dir finalize_ptrocos_timing.tcl] [file join $script_dir check_routed_timing.tcl] [file join $script_dir optimize_ptrocos_rom.tcl]]
foreach run [get_runs {synth_1 impl_1}] {
    set_property AUTO_INCREMENTAL_CHECKPOINT 0 $run
    set_property INCREMENTAL_CHECKPOINT {} $run
    # The GUI implementation process has also terminated in automatic reports,
    # before our post-route hook. Keep every report, but serialize their execution
    # to avoid the parallel-report path while preserving timing/DRC acceptance.
    set_property GEN_REPORTS_PARALLEL 0 $run
}
set impl [get_runs impl_1]
set_property STEPS.PLACE_DESIGN.TCL.PRE [file join $script_dir prepare_ptrocos_timing.tcl] $impl
set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE ExtraPostPlacementOpt $impl
set_property STEPS.PLACE_DESIGN.TCL.POST [file join $script_dir optimize_ptrocos_rom.tcl] $impl
set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true $impl
set_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore $impl
set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE AggressiveExplore $impl
set_property STEPS.ROUTE_DESIGN.TCL.POST [file join $script_dir finalize_ptrocos_timing.tcl] $impl
set_property STEPS.WRITE_BITSTREAM.TCL.PRE [file join $script_dir check_routed_timing.tcl] $impl
set published_bit [file join $out ptrocos_${ptrocos_firmware}.bit]
if {$project_folder eq "vivado"} {set published_bit [file join $out rv32_realtime_scope.bit]}
ddca_configure_guard $project_file $ptrocos_firmware $published_bit \
    [file join $out ptrocos.runs impl_1 ${board_top}_placed.dcp] \
    [file join $script_dir optimize_ptrocos_rom.tcl]
ddca_guard finish project $project_file $ptrocos_firmware
puts "PTROCOS PROJECT CREATED: $out"
