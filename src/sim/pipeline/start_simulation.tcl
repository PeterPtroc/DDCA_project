# 主工程的行为仿真入口：显示分组波形并运行程序，保留实时会话供逐拍观察。
source -encoding utf-8 [file join [file dirname [info script]] waves.tcl]
if {[get_value -radix unsigned /tb_pipeline_demo/done] ne "1"} {
    run all
}
pipeline_show_results
puts "Waveforms are ready. Use Restart before running the program again."
