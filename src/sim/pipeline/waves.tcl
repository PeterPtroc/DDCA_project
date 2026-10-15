# 在设计展开后加载此脚本；波形组名对应概念上的五级流水线。
proc pipeline_add_waves {} {
  set tb /tb_pipeline_demo
  create_wave_config pipeline_demo
  # 关键波形直接放在顶层，即使下面的详细分组收起，也能看到执行过程。
  add_wave $tb/clk $tb/rst
  foreach signal {IF_text ID_text EX_text MEM1_text MEM2_text WB_text} {
      add_wave -radix ascii $tb/$signal
  }
  foreach signal {remaining accumulator output_value finished} {
      add_wave -radix dec $tb/$signal
  }
  add_wave $tb/stalled $tb/flushed
  add_wave -radix unsigned $tb/dut/fwd_a $tb/dut/fwd_b
  foreach name {Results Control IF ID EX MEM WB Hazards CRC} {set groups($name) [add_wave_group $name]}
  foreach signal {pointer remaining accumulator current_value output_value finished loads branches reads writes} {
      add_wave -into $groups(Results) -radix dec $tb/$signal
  }
  add_wave -into $groups(CRC) -radix hex $tb/accumulator $tb/output_value
  add_wave -into $groups(CRC) $tb/crc_demo $tb/crc_event $tb/crc_count
  add_wave -into $groups(Control) $tb/clk $tb/rst $tb/cycle $tb/done
  foreach {group text signals} {
      IF IF_text {ia}
      ID ID_text {dut/ifid_valid dut/ifid_pc dut/ifid_insn dut/dec_imm dut/dec_alu_op dut/dec_alu_src_imm dut/dec_reg_we dut/dec_mem_re dut/dec_mem_we dut/dec_wb_mem dut/dec_branch}
      EX EX_text {dut/idex_valid dut/idex_pc dut/ex_a dut/ex_b_reg dut/alu_b dut/ex_result dut/idex_alu_op dut/idex_alu_src_imm dut/idex_reg_we dut/idex_mem_re dut/idex_mem_we dut/idex_wb_mem dut/idex_branch}
      MEM MEM1_text {dut/exmem_valid dut/exmem_pc dut/exmem_reg_we dut/exmem_mem_re dut/exmem_mem_we dv we da wd rd}
      MEM MEM2_text {dut/mem2_valid dut/mem2_pc dut/mem2_reg_we dut/mem2_wb_mem}
      WB WB_text {retired rpc rd_we dest result}
  } {
      add_wave -into $groups($group) -radix ascii $tb/$text
      foreach signal $signals {add_wave -into $groups($group) -radix hex $tb/$signal}
  }
  foreach signal {stalled flushed dut/fwd_a dut/fwd_b dut/redirect_target stalls flushes forwards commits} {
      add_wave -into $groups(Hazards) $tb/$signal
  }
}
pipeline_add_waves

# Vivado 将时间缩放保存在 WCFG 中；重载显示配置不会关闭实时仿真。
proc pipeline_show_results {} {
    set path [file join [pwd] pipeline_view_[pid].wcfg]
    save_wave_config $path
    set stream [open $path r]
    fconfigure $stream -encoding utf-8
    set config [read $stream]
    close $stream
    # 周期编号在 45 ns 开始，每拍 10 ns；完成标记后 1 ns 停止。
    set cursor_ps [expr {([get_value -radix unsigned /tb_pipeline_demo/cycle]*10+36)*1000}]
    set end_ps [expr {(($cursor_ps+99999)/100000)*100000}]
    set zoom [format {<zoom_setting>
      <ZoomStartTime time="0 ps"></ZoomStartTime>
      <ZoomEndTime time="%d ps"></ZoomEndTime>
      <Cursor1Time time="%d ps"></Cursor1Time>
   </zoom_setting>} $end_ps $cursor_ps]
    if {![regsub {(?s)<zoom_setting>.*?</zoom_setting>} $config $zoom config]} {
        error "The waveform configuration has no zoom settings."
    }
    set stream [open $path w]
    fconfigure $stream -encoding utf-8 -translation lf
    puts -nonewline $stream $config
    close $stream
    close_wave_config
    open_wave_config $path
}
