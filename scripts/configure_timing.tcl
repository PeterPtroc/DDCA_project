# Shared GUI/batch implementation recipe. Source after opening the project.
set ddca_timing_dir [file dirname [file normalize [info script]]]
foreach ddca_hook {finalize_timing.tcl check_routed_timing.tcl publish_bitstream.tcl} {
    set ddca_hook_path [file join $ddca_timing_dir $ddca_hook]
    if {[llength [get_files -quiet $ddca_hook_path]] == 0} {
        add_files -fileset utils_1 -norecurse $ddca_hook_path
    }
}
set ddca_impl [get_runs impl_1]
# Keep GUI rebuilds and batch builds independent of old timing checkpoints.
foreach ddca_run [get_runs {synth_1 impl_1}] {
    set_property AUTO_INCREMENTAL_CHECKPOINT 0 $ddca_run
    set_property INCREMENTAL_CHECKPOINT {} $ddca_run
}
set_property STEPS.PLACE_DESIGN.ARGS.DIRECTIVE ExtraPostPlacementOpt $ddca_impl
set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED true $ddca_impl
set_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore $ddca_impl
set_property STEPS.ROUTE_DESIGN.ARGS.DIRECTIVE AggressiveExplore $ddca_impl
# The post-route hook owns the conditional retry and final timing reports.
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED false $ddca_impl
set_property STEPS.ROUTE_DESIGN.TCL.POST [file join $ddca_timing_dir finalize_timing.tcl] $ddca_impl
set_property STEPS.WRITE_BITSTREAM.TCL.PRE [file join $ddca_timing_dir check_routed_timing.tcl] $ddca_impl
set_property STEPS.WRITE_BITSTREAM.TCL.POST [file join $ddca_timing_dir publish_bitstream.tcl] $ddca_impl
puts "TIMING CONFIGURED: setup WNS >= 0.100 ns; no setup/hold violations"
