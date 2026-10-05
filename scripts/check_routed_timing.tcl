# Also runs immediately before GUI bitgen, including resumed implementation runs.
set ddca_setup_path [get_timing_paths -quiet -delay_type max -max_paths 1]
set ddca_hold_path [get_timing_paths -quiet -delay_type min -max_paths 1]
if {[llength $ddca_setup_path] == 0 || [llength $ddca_hold_path] == 0} {
    error "Timing analysis did not return both setup and hold paths"
}
set ddca_setup_wns [get_property SLACK $ddca_setup_path]
set ddca_hold_wns [get_property SLACK $ddca_hold_path]
puts "TIMING: setup WNS=$ddca_setup_wns ns, hold WNS=$ddca_hold_wns ns"
# A nonnegative worst slack also proves that the total negative slack is zero.
if {$ddca_setup_wns < 0.100 || $ddca_hold_wns < 0.000} {
    error "Timing margin failed: require setup WNS >= 0.100 ns and hold WNS >= 0.000 ns"
}
puts "TIMING MARGIN PASS"
