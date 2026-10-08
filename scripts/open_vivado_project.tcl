# Reuse only a project whose branch, manifest and firmware still match.
set script_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $script_dir ..]]
cd $root
source [file join $script_dir build_guard.tcl]
set project_file [file join $root build vivado ptrocos.xpr]
if {[ddca_guard prepare project $project_file elf] eq "ready"} {
    open_project $project_file
} else {
    source [file join $script_dir create_vivado_project.tcl]
}
puts "VIVADO PROJECT READY: $project_file"
