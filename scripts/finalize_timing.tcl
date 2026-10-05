# Shared final routing/signoff hook. Keep the 100 MHz XDC and path exceptions.
set ddca_timing_dir [file dirname [file normalize [info script]]]
set ddca_build_dir [file normalize [file join $ddca_timing_dir .. build vivado]]
set ddca_report_dir [file join $ddca_build_dir reports]
file mkdir $ddca_report_dir

set ddca_preliminary_path [get_timing_paths -quiet -delay_type max -max_paths 1]
if {[llength $ddca_preliminary_path] != 0 &&
    [get_property SLACK $ddca_preliminary_path] >= -0.500 &&
    [get_property SLACK $ddca_preliminary_path] < 0.100} {
    puts "TIMING RETRY: post-route WNS=[get_property SLACK $ddca_preliminary_path] ns"
    phys_opt_design -directive AggressiveExplore
    route_design -directive NoTimingRelaxation
}
write_checkpoint -force [file join $ddca_build_dir rv32_realtime_scope_routed.dcp]
report_utilization -hierarchical -file [file join $ddca_report_dir utilization_routed.rpt] -force
report_timing_summary -delay_type min_max -report_unconstrained -check_timing_verbose \
    -max_paths 20 -file [file join $ddca_report_dir timing_summary_routed.rpt] \
    -pb [file join [pwd] nexys_a7_top_timing_summary_routed.pb] \
    -rpx [file join [pwd] nexys_a7_top_timing_summary_routed.rpx]
# Standard run reports are emitted before the POST hook. Refresh the GUI's
# timing report too, so a retry cannot leave a stale pre-optimization result.
file copy -force [file join $ddca_report_dir timing_summary_routed.rpt] \
    [file join [pwd] nexys_a7_top_timing_summary_routed.rpt]
report_clock_utilization -file [file join $ddca_report_dir clock_utilization_routed.rpt]
report_route_status -file [file join $ddca_report_dir route_status.rpt]
check_timing -verbose -file [file join $ddca_report_dir check_timing_routed.rpt]
report_drc -name final_drc -file [file join $ddca_report_dir drc_routed.rpt]
report_methodology -file [file join $ddca_report_dir methodology_routed.rpt]

source [file join $ddca_timing_dir check_routed_timing.tcl]
set ddca_blocking_drc {}
foreach violation [get_drc_violations -quiet] {
    set severity [get_property SEVERITY $violation]
    if {$severity eq "Error" || $severity eq "Critical Warning"} {
        lappend ddca_blocking_drc "[get_property ID $violation] ($severity)"
    }
}
if {[llength $ddca_blocking_drc] != 0} {
    error "Blocking DRC violations: $ddca_blocking_drc"
}
puts "IMPLEMENTATION PASS"
puts "DRC PASS"
