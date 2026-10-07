# Generate the PtrocOS MIG and its simulation model.
set root [file normalize [file join [file dirname [info script]] ..]]
cd $root
set out [file join $root build ptrocos_ddr2]
file mkdir $out
create_project ptrocos_ddr2 $out -part xc7a100tcsg324-1 -force
create_ip -name mig_7series -vendor xilinx.com -library ip -version 4.2 -module_name ptrocos_ddr2_mig
source [file join $root scripts configure_ptrocos_mig.tcl]
report_ip_status -file [file join $out ip_status.rpt]
puts "DDR2 MIG GENERATED at $out; calibration and board validation remain required"
