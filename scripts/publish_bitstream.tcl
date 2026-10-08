set script_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $script_dir ..]]
source [file join $script_dir build_guard.tcl]
set bitstream_file [file join $root build vivado rv32_realtime_scope.bit]
file copy -force [file join [pwd] nexys_a7_top.bit] $bitstream_file
ddca_guard finish bitstream $bitstream_file
puts "BITSTREAM PASS: $bitstream_file"
