set script_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $script_dir ..]]
cd $root

open_project [file join $root build vivado rv32_realtime_scope.xpr]
synth_design -top nexys_a7_top -part xc7a100tcsg324-1

set unconstrained_pins {}
set default_iostandard {}
foreach port [get_ports] {
    if {[get_property PACKAGE_PIN $port] eq ""} {
        lappend unconstrained_pins [get_property NAME $port]
    }

    set io_standard [get_property IOSTANDARD $port]
    if {$io_standard eq "" || $io_standard eq "DEFAULT"} {
        lappend default_iostandard [get_property NAME $port]
    }
}

if {[llength $unconstrained_pins] != 0} {
    error "Unconstrained top-level pins: $unconstrained_pins"
}
if {[llength $default_iostandard] != 0} {
    error "Top-level pins with default I/O standard: $default_iostandard"
}

report_io -file [file join $root build vivado synthesis_io.rpt] -force
report_utilization -file [file join $root build vivado utilization_synth.rpt] -force
puts "SYNTHESIS PASS"
close_project
