# Reject stale firmware, including nonempty HEX files from another branch.
set ddca_script_dir [file dirname [file normalize [info script]]]
set ddca_root [file normalize [file join $ddca_script_dir ..]]
source [file join $ddca_script_dir build_guard.tcl]
set ddca_firmware_file [ddca_check_firmware]
reset_msg_config -id {Synth 8-4445} -default_severity
set_msg_config -id {Synth 8-4445} -new_severity ERROR
