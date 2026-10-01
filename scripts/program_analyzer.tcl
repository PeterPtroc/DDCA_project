# Program the signed-off real-time scope bitstream on the first attached Nexys A7-100T.
# Run from PowerShell:
#   vivado -mode batch -source scripts/program_analyzer.tcl
set script_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $script_dir ..]]
set bitstream_file [file join $root build vivado rv32_realtime_scope.bit]

if {![file exists $bitstream_file]} {
    error "Bitstream not found: run scripts/build_bitstream.tcl first"
}

open_hw_manager
# This Windows host reserves TCP 3034..3133, which includes Vivado's default
# 3121.  Use an unreserved local hw_server port; a caller may start it with:
# hw_server -s tcp::31234 -p0
connect_hw_server -url TCP:localhost:31234 -allow_non_jtag
set targets [get_hw_targets -quiet]
if {[llength $targets] == 0} {
    error "No JTAG hardware target found; connect and power the Nexys A7-100T"
}

open_hw_target [lindex $targets 0]
set devices [get_hw_devices -quiet xc7a100t*]
if {[llength $devices] == 0} {
    error "No xc7a100t device found on [lindex $targets 0]"
}

set device [lindex $devices 0]
current_hw_device $device
refresh_hw_device -update_hw_probes false $device
set_property PROGRAM.FILE $bitstream_file $device
program_hw_devices $device
refresh_hw_device -update_hw_probes false $device
puts "PROGRAM PASS: $device <- $bitstream_file"

close_hw_target
disconnect_hw_server
close_hw_manager
