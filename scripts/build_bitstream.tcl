# Clean synthesis/implementation using exactly the configured GUI runs.
#   vivado -mode batch -source scripts/build_bitstream.tcl
set script_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $script_dir ..]]
set project_file [file join $root build vivado rv32_realtime_scope.xpr]
cd $root
if {[info exists ::env(PC_NEXT_STYLE)]} {
    set pc_next_style $::env(PC_NEXT_STYLE)
} else {
    set pc_next_style 0
}
if {$pc_next_style ni {0 1}} {
    error "PC_NEXT_STYLE must be 0 (PC CE) or 1 (pc_next)"
}

if {[file exists $project_file]} {
    open_project $project_file
} else {
    source [file join $script_dir create_vivado_project.tcl]
}
source [file join $script_dir configure_firmware.tcl]
source [file join $script_dir configure_timing.tcl]
# Preserve the absolute firmware path and any other existing generics.
set build_generics {}
foreach generic [get_property generic [get_filesets sources_1]] {
    if {![string match {CPU_PC_NEXT_STYLE=*} $generic]} {
        lappend build_generics $generic
    }
}
lappend build_generics "CPU_PC_NEXT_STYLE=$pc_next_style"
set_property generic $build_generics [get_filesets sources_1]

# Do not reuse a stale or incremental checkpoint when measuring timing margin.
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property STATUS [get_runs synth_1]] ne "synth_design Complete!"} {
    error "Synthesis failed: [get_property STATUS [get_runs synth_1]]"
}
puts "SYNTHESIS PASS"

# finalize_timing.tcl checks routed WNS >= +0.100 ns, hold and DRC. Bitgen's
# PRE hook checks the margin again; its POST hook publishes the canonical bit.
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property STATUS [get_runs impl_1]] ne "write_bitstream Complete!"} {
    error "Implementation/bitstream failed: [get_property STATUS [get_runs impl_1]]"
}
puts "BITSTREAM PASS: [file join $root build vivado rv32_realtime_scope.bit]"
close_project
