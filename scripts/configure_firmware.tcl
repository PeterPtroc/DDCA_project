# Refresh firmware dependencies and parameters in a new or existing Vivado project.
source [file join [file dirname [file normalize [info script]]] check_firmware.tcl]
set ddca_firmware_objects [get_files -quiet $ddca_firmware_file]
if {[llength $ddca_firmware_objects] == 0} {
    add_files -fileset sources_1 -norecurse $ddca_firmware_file
    set ddca_firmware_objects [get_files $ddca_firmware_file]
}
set_property file_type {Memory Initialization Files} $ddca_firmware_objects
set_property used_in_synthesis true $ddca_firmware_objects
set_property used_in_simulation true $ddca_firmware_objects

# Absolute paths work in GUI synthesis/simulation run directories, including paths with spaces.
foreach ddca_fileset [get_filesets -quiet {sources_1 sim_1}] {
    if {[get_property top $ddca_fileset] ne "nexys_a7_top"} { continue }
    set ddca_generics {}
    foreach ddca_generic [get_property generic $ddca_fileset] {
        if {![string match {IMEM_HEX=*} $ddca_generic]} {
            lappend ddca_generics $ddca_generic
        }
    }
    lappend ddca_generics "IMEM_HEX=\"$ddca_firmware_file\""
    set_property generic $ddca_generics $ddca_fileset
}
set_property STEPS.SYNTH_DESIGN.TCL.PRE [file join $ddca_script_dir check_firmware.tcl] [get_runs synth_1]
update_compile_order -fileset sources_1
puts "FIRMWARE CONFIGURED: $ddca_firmware_file"
