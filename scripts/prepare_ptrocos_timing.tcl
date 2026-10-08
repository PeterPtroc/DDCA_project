# Give placement and routing a setup margin to optimize against. Keep physical
# optimization before routing: Vivado 2024.2 can terminate inside post-route
# AggressiveExplore when moving the replicated CPU instruction-address drivers.
# finalize_ptrocos_timing.tcl restores the acceptance constraints before checks.
set ptrocos_optimize_clocks [get_clocks -of_objects [get_pins {
    cpu_clock/O pixel_clock/O
    memory/u_ptrocos_ddr2_mig_mig/u_ddr2_infrastructure/u_bufg_clkdiv0/O
}]]
if {[llength $ptrocos_optimize_clocks]!=3} {
    error "Missing functional clock for timing optimization"
}
set_clock_uncertainty -setup 0.250 $ptrocos_optimize_clocks
puts "PTROCOS PRE-ROUTE TIMING TARGET: 0.250ns setup uncertainty"
