# Additional experimental I/O. Pin source: Digilent Nexys-A7-100T-Master.xdc.
set_property -dict {PACKAGE_PIN A3 IOSTANDARD LVCMOS33} [get_ports {vga_red[0]}]
set_property -dict {PACKAGE_PIN B4 IOSTANDARD LVCMOS33} [get_ports {vga_red[1]}]
set_property -dict {PACKAGE_PIN C5 IOSTANDARD LVCMOS33} [get_ports {vga_red[2]}]
set_property -dict {PACKAGE_PIN A4 IOSTANDARD LVCMOS33} [get_ports {vga_red[3]}]
set_property -dict {PACKAGE_PIN C6 IOSTANDARD LVCMOS33} [get_ports {vga_green[0]}]
set_property -dict {PACKAGE_PIN A5 IOSTANDARD LVCMOS33} [get_ports {vga_green[1]}]
set_property -dict {PACKAGE_PIN B6 IOSTANDARD LVCMOS33} [get_ports {vga_green[2]}]
set_property -dict {PACKAGE_PIN A6 IOSTANDARD LVCMOS33} [get_ports {vga_green[3]}]
set_property -dict {PACKAGE_PIN B7 IOSTANDARD LVCMOS33} [get_ports {vga_blue[0]}]
set_property -dict {PACKAGE_PIN C7 IOSTANDARD LVCMOS33} [get_ports {vga_blue[1]}]
set_property -dict {PACKAGE_PIN D7 IOSTANDARD LVCMOS33} [get_ports {vga_blue[2]}]
set_property -dict {PACKAGE_PIN D8 IOSTANDARD LVCMOS33} [get_ports {vga_blue[3]}]
set_property -dict {PACKAGE_PIN B11 IOSTANDARD LVCMOS33} [get_ports vga_hsync]
set_property -dict {PACKAGE_PIN B12 IOSTANDARD LVCMOS33} [get_ports vga_vsync]
set_property -dict {PACKAGE_PIN F4 IOSTANDARD LVCMOS33} [get_ports ps2_clk]
set_property -dict {PACKAGE_PIN B2 IOSTANDARD LVCMOS33} [get_ports ps2_data]
# Asynchronous PS/2 pins reach only the first stage of each 2-FF synchronizer.
set ps2_first [get_cells -hier -regexp {.*keyboard/(clock|data)_sync_reg\[0\]$}]
set_false_path -from [get_ports {ps2_clk ps2_data}] -to [get_pins -of_objects $ps2_first -filter {REF_PIN_NAME == D}]
# VGA is analog video without an external capture-clock timing contract.
# Registered sync/color signals and their local pipeline remain timed.
set_false_path -to [get_ports {vga_red[*] vga_green[*] vga_blue[*] vga_hsync vga_vsync}]
