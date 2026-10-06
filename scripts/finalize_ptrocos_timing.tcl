set script_dir [file dirname [file normalize [info script]]]
if {[info exists ptrocos_output_root]} {
    # open_checkpoint creates an in-memory project rooted at the caller's cwd.
    set out [file normalize $ptrocos_output_root]
} else {
    set out [file normalize [get_property DIRECTORY [current_project]]]
}
# Implementation hooks use an in-memory project rooted inside ptrocos.runs.
if {[file tail [file dirname $out]] eq "ptrocos.runs"} {
    set out [file dirname [file dirname $out]]
}
set reports [file join $out reports]
file mkdir $reports
foreach {clock_pin expected_period} {cpu_clock/O 10.000 reference_clock/O 5.000 pixel_clock/O 39.682540} {
    set clocks [get_clocks -of_objects [get_pins $clock_pin]]
    if {[llength $clocks]!=1 || abs([get_property PERIOD $clocks]-$expected_period)>0.001} {
        error "Incorrect implemented clock at $clock_pin: $clocks, expected ${expected_period}ns"
    }
    puts "PTROCOS CLOCK VERIFIED: $clock_pin [get_property PERIOD $clocks] ns"
}
foreach pattern {
    {.*ddr_cdc/request_sync_reg\[0\]$}
    {.*ddr_cdc/completion_sync_reg\[0\]$}
    {.*ddr_cdc/payload_(we|addr|data|strobes)_reg(\[[0-9]+\])?$}
    {.*ddr_cdc/target_(we|addr|wdata|wstrb)_reg(\[[0-9]+\])?$}
    {.*ddr_cdc/response_(data|error)_reg(\[[0-9]+\])?$}
    {.*ddr_cdc/source_(rdata|error)_reg(\[[0-9]+\])?$}
    {.*(cpu|ui)_reset_sync_reg\[[01]\]$}
    {.*pixel_reset_sync_reg\[[01]\]$}
    {.*text_display/register_cdc/request_sync_reg\[0\]$}
    {.*text_display/register_cdc/completion_sync_reg\[0\]$}
    {.*text_display/register_cdc/payload_(we|addr|data|strobes)_reg(\[[0-9]+\])?$}
    {.*text_display/register_cdc/target_(we|addr|wdata|wstrb)_reg(\[[0-9]+\])?$}
    {.*text_display/register_cdc/response_data_reg(\[[0-9]+\])?$}
    {.*text_display/register_cdc/source_rdata_reg(\[[0-9]+\])?$}
    {.*keyboard/(clock|data)_sync_reg\[0\]$}
    {.*soc/sd/(miso|detect)_sync_reg\[0\]$}
} {
    if {![llength [get_cells -hier -quiet -regexp $pattern]]} {
        error "Missing mailbox constraint endpoint: $pattern"
    }
}
set preliminary [get_timing_paths -quiet -delay_type max -max_paths 1]
if {[llength $preliminary] && [get_property SLACK $preliminary]>=-0.500 &&
    [get_property SLACK $preliminary]<0.100} {
    phys_opt_design -directive AggressiveExplore
    route_design -directive NoTimingRelaxation
}
write_checkpoint -force [file join $out ptrocos_routed.dcp]
report_timing_summary -delay_type min_max -report_unconstrained -check_timing_verbose -max_paths 20 -file [file join $reports timing_summary.rpt]
set timing_file [open [file join $reports timing_summary.rpt] r]
set timing_text [read $timing_file]
close $timing_file
if {![regexp -line {^\s+(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+\d+\s+\d+\s+(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+\d+\s+\d+\s+(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+\d+\s+\d+\s*$} \
    $timing_text all wns tns whs ths wpws tpws]} {
    error "Cannot parse routed timing summary acceptance fields"
}
if {$wns<0.100 || $tns!=0 || $whs<0 || $ths!=0 || $wpws<0 || $tpws!=0} {
    error "PtrocOS timing margin failed: WNS=$wns TNS=$tns WHS=$whs THS=$ths WPWS=$wpws TPWS=$tpws"
}
report_utilization -hierarchical -file [file join $reports utilization.rpt]
report_clock_utilization -file [file join $reports clocks.rpt]
report_clock_interaction -file [file join $reports clock_interaction.rpt]
report_cdc -details -file [file join $reports cdc.rpt]
report_exceptions -coverage -file [file join $reports exceptions.rpt]
check_timing -verbose -file [file join $reports check_timing.rpt]
report_drc -name ptrocos_drc -file [file join $reports drc.rpt]
report_methodology -file [file join $reports methodology.rpt]
source [file join $script_dir check_routed_timing.tcl]
set blocking {}
foreach violation [get_drc_violations -quiet] {
    if {[get_property SEVERITY $violation] in {Error {Critical Warning}}} {
        lappend blocking "[get_property ID $violation] ([get_property SEVERITY $violation])"
    }
}
if {[llength $blocking]} { error "Blocking DRC: $blocking" }
puts "PTROCOS ROUTED TIMING/DRC PASS"
