set script_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $script_dir ..]]
cd $root
source [file join $script_dir build_guard.tcl]
set project_file [file join $root build vivado rv32_realtime_scope.xpr]
if {[ddca_guard prepare project $project_file] eq "ready"} {
    open_project $project_file
} else {
    source [file join $script_dir create_vivado_project.tcl]
}
puts "VIVADO PROJECT READY: $project_file"
