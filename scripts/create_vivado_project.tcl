# Compatibility entry for the unchanged README quick start.
set script_dir [file dirname [file normalize [info script]]]
set ptrocos_firmware elf
set ptrocos_project_folder vivado
source [file join $script_dir create_ptrocos_project.tcl]
add_files -fileset utils_1 -norecurse [file join $script_dir publish_bitstream.tcl]
set_property STEPS.WRITE_BITSTREAM.TCL.POST [file join $script_dir publish_bitstream.tcl] [get_runs impl_1]
