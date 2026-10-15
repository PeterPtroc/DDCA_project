# 将课设演示登记到当前 Vivado 工程，不启动或关闭仿真。
namespace eval ddca_pipeline {
    variable root [file normalize [file join [file dirname [info script]] .. .. ..]]

    proc register {} {
        variable root
        if {[current_project -quiet] eq ""} {error "Open a Vivado project before adding the pipeline simulations."}
        set previous [current_fileset -simset]
        set sources {}
        foreach module {alu crc16_unit decoder hazard_unit imm_gen regfile rv32m_unit rv32im_decoder rv32im_core} {
            lappend sources [file join $root src rtl cpu ${module}.v]
        }
        lappend sources [file join $root src sim pipeline tb_pipeline_demo.sv]

        foreach name {sim_pipeline sim_pipeline_crc} {
            if {![llength [get_filesets -quiet $name]]} {create_fileset -simset $name}
            set simset [get_filesets $name]
            # 仅编译演示所需的 CPU 和测试平台，不引入板级 MIG 或固件依赖。
            set_property SOURCE_SET {} $simset
            foreach path $sources {
                if {![llength [get_files -quiet -of_objects $simset $path]]} {
                    add_files -fileset $name -norecurse $path
                }
            }
            set_property top tb_pipeline_demo $simset
            set_property top_auto_set false $simset
            set_property generic {} $simset
            set_property xsim.elaborate.debug_level all $simset
            set_property xsim.simulate.custom_tcl [file join $root src sim pipeline start_simulation.tcl] $simset
            set_property xsim.simulate.runtime 0ns $simset
            if {$name eq "sim_pipeline_crc"} {
                set_property -dict {xsim.simulate.xsim.more_options {-testplusarg CRC_DEMO}} $simset
            } else {
                set_property xsim.simulate.xsim.more_options {} $simset
            }
            update_compile_order -fileset $name
        }

        # 汇编和波形脚本在工程中可见，但不加入 HDL 综合源。
        foreach relative {array_sum.S crc_demo.S waves.tcl start_simulation.tcl add_to_project.tcl} {
            set path [file join $root src sim pipeline $relative]
            if {![llength [get_files -quiet -of_objects [get_filesets utils_1] $path]]} {
                add_files -fileset utils_1 -norecurse $path
            }
        }
        if {$previous in {sim_pipeline sim_pipeline_crc}} {
            current_fileset -simset $previous
        } else {
            current_fileset -simset sim_pipeline
        }
        puts "PIPELINE SIMULATIONS READY: sim_pipeline (array sum), sim_pipeline_crc (CRC)."
        puts "Use Run Simulation > Run Behavioral Simulation in this project."
    }
}
ddca_pipeline::register
