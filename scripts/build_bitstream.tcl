# Complete Windows Vivado implementation flow. Run from PowerShell:
#   vivado -mode batch -source scripts/build_bitstream.tcl
set script_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $script_dir ..]]
set build_dir [file join $root build vivado]
set project_file [file join $build_dir rv32_realtime_scope.xpr]
set report_dir [file join $build_dir reports]
set bitstream_file [file join $build_dir rv32_realtime_scope.bit]
if {[info exists ::env(PC_NEXT_STYLE)]} {
    set pc_next_style $::env(PC_NEXT_STYLE)
} else {
    set pc_next_style 0
}
if {$pc_next_style ni {0 1}} {
    error "PC_NEXT_STYLE must be 0 (PC CE) or 1 (pc_next)"
}

source [file join $script_dir open_vivado_project.tcl]
file mkdir $report_dir
ddca_guard begin bitstream $bitstream_file

# Keep the direct flow in the repository root so imem's generated firmware path
# resolves identically in simulation and synthesis.
cd $root
synth_design -top nexys_a7_top -part xc7a100tcsg324-1 \
    -generic CPU_PC_NEXT_STYLE=$pc_next_style
puts "SYNTHESIS PASS"
write_checkpoint -force [file join $build_dir rv32_realtime_scope_synth.dcp]
opt_design
place_design -directive ExtraPostPlacementOpt
phys_opt_design -directive AggressiveExplore
route_design -directive AggressiveExplore

# A marginal post-route result on this design is dominated by CPU forwarding
# and ALU routing delay.  The plan requires investigation below +0.1 ns, so
# give Vivado one legal timing-focused retry for both near misses and failures
# before applying the hard timing gate below.  The clock constraint and path
# exceptions are unchanged.
set preliminary_setup_path [get_timing_paths -quiet -delay_type max -max_paths 1]
if {[llength $preliminary_setup_path] != 0 &&
    [get_property SLACK $preliminary_setup_path] < 0.100} {
    puts "TIMING RETRY: post-route WNS=[get_property SLACK $preliminary_setup_path] ns"
    phys_opt_design -directive AggressiveExplore
    route_design -directive NoTimingRelaxation
}
write_checkpoint -force [file join $build_dir rv32_realtime_scope_routed.dcp]

report_utilization -hierarchical -file [file join $report_dir utilization_routed.rpt] -force
report_timing_summary -delay_type min_max -report_unconstrained -check_timing_verbose \
    -max_paths 20 -file [file join $report_dir timing_summary_routed.rpt]
report_clock_utilization -file [file join $report_dir clock_utilization_routed.rpt]
check_timing -verbose -file [file join $report_dir check_timing_routed.rpt]
report_drc -name final_drc -file [file join $report_dir drc_routed.rpt]
report_methodology -file [file join $report_dir methodology_routed.rpt]

set setup_path [get_timing_paths -quiet -delay_type max -max_paths 1]
set hold_path [get_timing_paths -quiet -delay_type min -max_paths 1]
if {[llength $setup_path] == 0 || [llength $hold_path] == 0} {
    error "Timing analysis did not return both setup and hold paths"
}

set setup_wns [get_property SLACK $setup_path]
set hold_wns [get_property SLACK $hold_path]
puts "TIMING: setup WNS=$setup_wns ns, hold WNS=$hold_wns ns"
# The old build-only smoke check stopped after elaboration/synthesis and could
# produce a false green. Refuse bitstream generation when routed timing fails.
if {$setup_wns < 0.0 || $hold_wns < 0.0} {
    error "Timing failed: setup WNS=$setup_wns ns, hold WNS=$hold_wns ns"
}

set blocking_drc {}
foreach violation [get_drc_violations -quiet] {
    set severity [get_property SEVERITY $violation]
    if {$severity eq "Error" || $severity eq "Critical Warning"} {
        lappend blocking_drc "[get_property ID $violation] ($severity)"
    }
}
if {[llength $blocking_drc] != 0} {
    error "Blocking DRC violations: $blocking_drc"
}
puts "IMPLEMENTATION PASS"
puts "DRC PASS"

# Reaching bitgen now proves routing, setup/hold timing, and blocking DRCs all
# passed; it does not claim that warning-level findings or hardware tests passed.
write_bitstream -force $bitstream_file
ddca_guard finish bitstream $bitstream_file
puts "BITSTREAM PASS: $bitstream_file"
close_project
