# Reroute a placed checkpoint with the normal timing/DRC gate.
# No failed or unvalidated bitstream is emitted. Uses no RTL or firmware edits.
set script_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $script_dir ..]]
if {[llength $argv]<1 || [llength $argv]>2 || [lindex $argv 0] ni {ddr2 text shell storage graphics} ||
    ([llength $argv]==2 && [lindex $argv 1] ne "verify")} {error "Specify firmware: ddr2/text/shell/storage/graphics, optionally verify"}
set firmware [lindex $argv 0]
set folder [expr {$firmware eq "ddr2" ? "ptrocos_vivado" : "ptrocos_${firmware}_vivado"}]
set out [file join $root build $folder]
set ptrocos_output_root $out
set verify_only [expr {[llength $argv]==2}]
set checkpoint [expr {$verify_only ? [file join $out ptrocos_routed.dcp] :
    [file join $out ptrocos.runs impl_1 ptrocos_nexys_a7_top_placed.dcp]}]
if {![file isfile $checkpoint]} {error "Missing checkpoint: $checkpoint"}
open_project [file join $out ptrocos.xpr]
open_checkpoint $checkpoint
if {$firmware eq "graphics" && !$verify_only} {
    # Reapply the current bounded CDC constraints, including physical replicas.
    read_xdc [file join $root constraints ptrocos_graphics.xdc]
}
if {!$verify_only} {
    source [file join $script_dir optimize_ptrocos_rom.tcl]
    phys_opt_design -directive AggressiveExplore
    route_design -directive AggressiveExplore
}
source [file join $script_dir finalize_ptrocos_timing.tcl]
write_bitstream -force [file join $out ptrocos_${firmware}.bit]
puts "PTROCOS RESUMED BITSTREAM PASS: [file join $out ptrocos_${firmware}.bit]"
close_project
