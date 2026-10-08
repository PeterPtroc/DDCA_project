# Shared by GUI launch, batch builds, run hooks and programming scripts.
set ddca_guard_script [file join [file dirname [file normalize [info script]]] build_guard.py]
set ddca_default_variant freertos

proc ddca_guard {action kind artifact {variant ""} {extra {}}} {
    global ddca_guard_script ddca_default_variant
    if {$variant eq ""} {set variant $ddca_default_variant}
    set command [list python.exe -E $ddca_guard_script $action --kind $kind --file $artifact --variant $variant]
    if {$kind ne "firmware"} {lappend command --tool [version -short]}
    set command [concat $command $extra]
    # Success diagnostics on stderr (e.g. archive paths) must not look like failure.
    if {[catch {exec {*}$command 2>@1} output options]} {error $output}
    if {$output ne ""} {puts $output}
    return [lindex [split [string trim $output] \n] end]
}

proc ddca_firmware {{variant ""}} {
    global ddca_guard_script ddca_default_variant
    if {$variant eq ""} {set variant $ddca_default_variant}
    set root [file dirname [file dirname $ddca_guard_script]]
    if {$ddca_default_variant eq "elf"} {set variant ptrocos_$variant}
    return [file join $root build hex ${variant}.hex]
}

proc ddca_check_firmware {{variant ""}} {
    set firmware [ddca_firmware $variant]
    ddca_guard check firmware $firmware $variant
    return $firmware
}

proc ddca_configure_guard {project variant bitstream {placed ""} {place_hook ""}} {
    global ddca_guard_script
    set bridge [file join [file dirname $ddca_guard_script] build_guard.tcl]
    # Run subprocesses may not expose the parent project's run objects. Capture
    # explicit paths in generated hooks instead of guessing from the run cwd.
    set pre [file join [file dirname $project] build_guard_synthesis.tcl]
    set stream [open $pre w]
    puts $stream [list source $bridge]
    puts $stream [list ddca_guard check project $project $variant]
    puts $stream [list ddca_guard begin bitstream $bitstream $variant]
    close $stream
    if {![llength [get_files -quiet $pre]]} {add_files -fileset utils_1 -norecurse $pre}
    set_property STEPS.SYNTH_DESIGN.TCL.PRE $pre [get_runs synth_1]
    foreach run [get_runs {synth_1 impl_1}] {
        set_property AUTO_INCREMENTAL_CHECKPOINT 0 $run
        set_property INCREMENTAL_CHECKPOINT {} $run
    }
    if {$placed ne ""} {
        set post [file join [file dirname $project] build_guard_placed.tcl]
        set stream [open $post w]
        puts $stream [list source $bridge]
        if {$place_hook ne ""} {puts $stream [list source $place_hook]}
        puts $stream [list write_checkpoint -force $placed]
        puts $stream [list ddca_guard seal checkpoint $placed $variant [list --basis $bitstream]]
        close $stream
        if {![llength [get_files -quiet $post]]} {add_files -fileset utils_1 -norecurse $post}
        set_property STEPS.PLACE_DESIGN.TCL.POST $post [get_runs impl_1]
    }
    # Also used by route/bitgen hooks and the checkpoint resume entrypoint.
    set config [open [file join [file dirname $project] build_guard_config.tcl] w]
    puts $config [list set ddca_guard_variant $variant]
    puts $config [list set ddca_guard_bitstream $bitstream]
    close $config
}
