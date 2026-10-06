# Programs volatile FPGA configuration only, using an explicit hardware target.
# vivado -mode batch -source scripts/program_ptrocos.tcl -tclargs <target-url>
set root [file normalize [file join [file dirname [info script]] ..]]
set firmware ddr2
if {[llength $argv]==2 && [lindex $argv 1] in {ddr2 text shell storage graphics media video}} {set firmware [lindex $argv 1]}
if {$firmware eq "ddr2"} {set folder ptrocos_vivado} else {set folder ptrocos_${firmware}_vivado}
set bitstream [file join $root build $folder ptrocos_${firmware}.bit]
if {![file isfile $bitstream]} { error "Run build_ptrocos_bitstream.tcl first" }
if {[llength $argv]<1 || [llength $argv]>2 || ([llength $argv]==2 && [lindex $argv 1] ni {ddr2 text shell storage graphics media video})} { error "Specify target URL, optionally ddr2/text/shell/storage/graphics/media/video firmware" }
open_hw_manager
connect_hw_server -url TCP:localhost:31234 -allow_non_jtag
set target [get_hw_targets -quiet [lindex $argv 0]]
if {[llength $target]!=1} { error "JTAG target missing or ambiguous: [lindex $argv 0]" }
open_hw_target $target
set device [get_hw_devices -quiet xc7a100t*]
if {[llength $device]!=1} { error "Expected exactly one xc7a100t device on $target" }
current_hw_device $device
refresh_hw_device -update_hw_probes false $device
set_property PROGRAM.FILE $bitstream $device
program_hw_devices $device
puts "PTROCOS PROGRAM PASS: $device <- $bitstream"
close_hw_target
disconnect_hw_server
close_hw_manager
