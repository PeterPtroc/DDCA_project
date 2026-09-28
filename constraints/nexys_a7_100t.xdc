# Pin assignments intentionally remain a template until the official Digilent
# Nexys A7-100T master XDC is supplied. Do not invent package pins.
set_property IOSTANDARD LVCMOS33 [get_ports {clk100 reset uart_tx}]
create_clock -period 10.000 -name sys_clk [get_ports clk100]
