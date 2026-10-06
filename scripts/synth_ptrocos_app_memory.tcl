set root [file normalize [file join [file dirname [info script]] ..]]
cd $root
file mkdir build/ptrocos_elf
read_verilog src/rtl/memory/word_bus_cdc.v
read_verilog src/rtl/memory/ptrocos_app_memory.v
synth_design -top ptrocos_app_memory -part xc7a100tcsg324-1 -mode out_of_context
create_clock -name cpu_clk -period 10 [get_ports clk]
report_utilization -file build/ptrocos_elf/app-memory-utilization.rpt
report_timing_summary -file build/ptrocos_elf/app-memory-synth-timing.rpt
set brams [get_cells -hier -filter {REF_NAME =~ RAMB*}]
if {[llength $brams] != 4} {error "Expected four RAMB36 primitives for 16 KiB application RAM: $brams"}
foreach b $brams {
    if {[get_property REF_NAME $b] ne "RAMB36E1"} {error "Unexpected RAM primitive $b"}
}
write_checkpoint -force build/ptrocos_elf/app-memory-synth.dcp
puts "PTROCOS APP MEMORY SYNTH PASS RAMB36=4 same-falling-edge instruction/data ports"
