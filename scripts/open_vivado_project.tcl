# Recreate the quick-start project from the current PtrocOS source manifest.
# Old generated projects can still contain removed analyzer RTL.
set script_dir [file dirname [file normalize [info script]]]
source [file join $script_dir create_vivado_project.tcl]
puts "VIVADO PROJECT READY: [get_property DIRECTORY [current_project]]"
