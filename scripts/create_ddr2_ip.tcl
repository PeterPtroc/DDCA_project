# Generate the experiment's MIG independently of the original Vivado project.
set root [file normalize [file join [file dirname [info script]] ..]]
cd $root
set out [file join $root build ptrocos_ddr2]
file mkdir $out
create_project ptrocos_ddr2 $out -part xc7a100tcsg324-1 -force
create_ip -name mig_7series -vendor xilinx.com -library ip -version 4.2 -module_name ptrocos_ddr2_mig
set preset [file join $root third_party digilent nexys-a7-100t-mig.prj]
set_property CONFIG.XML_INPUT_FILE $preset [get_ips ptrocos_ddr2_mig]
generate_target all [get_ips ptrocos_ddr2_mig]
report_ip_status -file [file join $out ip_status.rpt]
puts "DDR2 MIG GENERATED at $out; calibration and board validation remain required"
