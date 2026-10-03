# Vivado batch project bootstrap. Run from the repository root:
#   vivado -mode batch -source scripts/create_vivado_project.tcl
set script_dir [file dirname [file normalize [info script]]]
set root [file normalize [file join $script_dir ..]]
cd $root
set build_dir [file join $root build vivado]
file mkdir $build_dir
create_project rv32_realtime_scope $build_dir -part xc7a100tcsg324-1 -force
# The course-design project deliberately lists every production RTL source.
set production_sources [list \
    [file join $root src rtl bus mmio_decoder.v] \
    [file join $root src rtl cpu alu.v] \
    [file join $root src rtl cpu crc16_unit.v] \
    [file join $root src rtl cpu decoder.v] \
    [file join $root src rtl cpu forwarding_unit.v] \
    [file join $root src rtl cpu hazard_unit.v] \
    [file join $root src rtl cpu imm_gen.v] \
    [file join $root src rtl cpu regfile.v] \
    [file join $root src rtl cpu rv32_core.v] \
    [file join $root src rtl memory dmem.v] \
    [file join $root src rtl memory imem.v] \
    [file join $root src rtl peripheral clint.v] \
    [file join $root src rtl peripheral button_debounce.v] \
    [file join $root src rtl peripheral button_mmio.v] \
    [file join $root src rtl peripheral edge_meter_scope.v] \
    [file join $root src rtl peripheral fixed_test_signals.v] \
    [file join $root src rtl peripheral gpio_mmio.v] \
    [file join $root src rtl peripheral input_sync.v] \
    [file join $root src rtl peripheral live_scope.v] \
    [file join $root src rtl peripheral perf_counter.v] \
    [file join $root src rtl peripheral rgb_status.v] \
    [file join $root src rtl peripheral scope_capture.v] \
    [file join $root src rtl peripheral sevenseg.v] \
    [file join $root src rtl peripheral timer_mmio.v] \
    [file join $root src rtl peripheral uart_mmio.v] \
    [file join $root src rtl peripheral uart_rx.v] \
    [file join $root src rtl peripheral uart_tx.v] \
    [file join $root src rtl top nexys_a7_top.v] \
    [file join $root src rtl top soc_top.v] \
]
add_files -norecurse $production_sources
add_files -fileset constrs_1 -norecurse [file join $root constraints nexys_a7_100t.xdc]
set_property top nexys_a7_top [current_fileset]
update_compile_order -fileset sources_1
puts "Vivado project created at $build_dir"
