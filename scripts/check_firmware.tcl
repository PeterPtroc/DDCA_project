# Shared guard for direct builds and GUI synthesis runs.
set ddca_script_dir [file dirname [file normalize [info script]]]
set ddca_root [file normalize [file join $ddca_script_dir ..]]
set ddca_firmware_file [file join $ddca_root build hex freertos.hex]
if {![file isfile $ddca_firmware_file] || ![file readable $ddca_firmware_file] ||
    [file size $ddca_firmware_file] == 0} {
    error "FreeRTOS firmware is missing, empty, or unreadable: $ddca_firmware_file. Run build_freertos.bat first."
}
# A missing ROM image must stop synthesis rather than produce an empty firmware image.
# The guard is sourced during project setup and again before synthesis.
# Replace any saved rule so repeated checks do not fail with Common 17-1361.
reset_msg_config -id {Synth 8-4445} -default_severity
set_msg_config -id {Synth 8-4445} -new_severity ERROR
