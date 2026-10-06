# Nexys A7-100T microSD SPI: DAT0=MISO, CMD=MOSI, DAT3=CS.
# Source: Digilent Nexys-A7-100T-Master.xdc and board reference manual section 11.
set_property -dict {PACKAGE_PIN C2 IOSTANDARD LVCMOS33} [get_ports sd_miso]
set_property -dict {PACKAGE_PIN A1 IOSTANDARD LVCMOS33} [get_ports sd_cd_n]
set_property -dict {PACKAGE_PIN B1 IOSTANDARD LVCMOS33 SLEW SLOW} [get_ports sd_sck]
set_property -dict {PACKAGE_PIN C1 IOSTANDARD LVCMOS33 SLEW SLOW} [get_ports sd_mosi]
set_property -dict {PACKAGE_PIN D2 IOSTANDARD LVCMOS33 SLEW SLOW} [get_ports sd_cs_n]
set_property -dict {PACKAGE_PIN E2 IOSTANDARD LVCMOS33 SLEW SLOW} [get_ports sd_reset]
# SCK is a registered, gated data output, not an internal clock. All engine
# registers remain timed at 100 MHz. Minimum half-period=4 CPU cycles (40 ns).
# External mode-0 setup/hold is checked by SPI edge simulation and real-card CRC;
# no synchronous input/output-delay contract is asserted for these ports.
set sd_first [get_cells -hier -regexp {.*soc/sd/(miso|detect)_sync_reg\[0\]$}]
# Endpoint existence is checked in finalize_ptrocos_timing.tcl (normal Tcl).
set_false_path -from [get_ports {sd_miso sd_cd_n}] -to [get_pins -of_objects $sd_first -filter {REF_PIN_NAME == D}]
set_false_path -to [get_ports {sd_sck sd_mosi sd_cs_n sd_reset}]
