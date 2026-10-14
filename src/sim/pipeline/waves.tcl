# Source after elaboration; group names follow the five conceptual stages.
set tb /tb_pipeline_demo
create_wave_config pipeline_demo
foreach name {Control IF ID EX MEM WB Hazards} {set groups($name) [add_wave_group $name]}
add_wave -into $groups(Control) $tb/clk $tb/rst $tb/cycle $tb/done
foreach {group text signals} {
    IF IF_text {ia}
    ID ID_text {dut/ifid_valid dut/ifid_pc dut/ifid_insn}
    EX EX_text {dut/idex_valid dut/idex_pc dut/ex_a dut/ex_b_reg dut/ex_result}
    MEM MEM1_text {dut/exmem_valid dut/exmem_pc dv we da wd rd}
    MEM MEM2_text {dut/mem2_valid dut/mem2_pc}
    WB WB_text {retired rpc rd_we dest result}
} {
    add_wave -into $groups($group) -radix ascii $tb/$text
    foreach signal $signals {add_wave -into $groups($group) -radix hex $tb/$signal}
}
foreach signal {stalled flushed dut/fwd_a dut/fwd_b dut/redirect_target stalls flushes forwards commits} {
    add_wave -into $groups(Hazards) $tb/$signal
}
