# Digilent Nexys A7-100T Master XDC; audio PWM is driven low or tri-stated.
set_property -dict { PACKAGE_PIN A11 IOSTANDARD LVCMOS33 SLEW SLOW } [get_ports aud_pwm]
set_property -dict { PACKAGE_PIN D12 IOSTANDARD LVCMOS33 SLEW SLOW } [get_ports aud_sd]
# The analog filter/amplifier has no external synchronous capture clock.
# Bound register-to-pin propagation to one CPU period, including OBUFT delay.
set audio_drivers [get_cells -hier -regexp {.*soc/audio/(running|bit_out)_reg(_replica(_[0-9]+)?)?$}]
set_max_delay 10.000 -datapath_only -from $audio_drivers -to [get_ports {aud_pwm aud_sd}]
set_min_delay 0.000 -from $audio_drivers -to [get_ports {aud_pwm aud_sd}]
