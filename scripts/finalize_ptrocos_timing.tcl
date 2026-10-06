set script_dir [file dirname [file normalize [info script]]]
if {[info exists ptrocos_output_root]} {
    # open_checkpoint creates an in-memory project rooted at the caller's cwd.
    set out [file normalize $ptrocos_output_root]
} else {
    set out [file normalize [get_property DIRECTORY [current_project]]]
}
# Implementation hooks use an in-memory project rooted inside ptrocos.runs.
if {[file tail [file dirname $out]] eq "ptrocos.runs"} {
    set out [file dirname [file dirname $out]]
}
set reports [file join $out reports]
file mkdir $reports
if {[llength [get_ports -quiet aud_pwm]]} {
    # The A7 analog supply owns the pull-up. Prove the implemented pin can only
    # sink current or float; a push-pull output would violate the board manual.
    set audio_net [get_nets -of_objects [get_ports aud_pwm]]
    set audio_buffer [get_cells -of_objects $audio_net -filter {REF_NAME == OBUFT}]
    if {[llength $audio_buffer]!=1} {error "Audio PWM must use one OBUFT"}
    set audio_i [get_pins -of_objects $audio_buffer -filter {REF_PIN_NAME == I}]
    set audio_i_net [get_nets -segments -of_objects $audio_i]
    set audio_ground [get_cells -of_objects $audio_i_net -filter {REF_NAME == GND}]
    if {![llength $audio_ground]} {error "Audio OBUFT data input must be constant zero"}
    foreach {port pin} {aud_pwm A11 aud_sd D12} {
        if {[get_property PACKAGE_PIN [get_ports $port]] ne $pin ||
            [get_property IOSTANDARD [get_ports $port]] ne "LVCMOS33"} {
            error "Incorrect audio pin assignment: $port"
        }
        set audio_paths [get_timing_paths -quiet -to [get_ports $port] -delay_type max -max_paths 100]
        if {![llength $audio_paths]} {error "Missing register-to-audio-pin paths: $port"}
        foreach path $audio_paths {
            if {[get_property EXCEPTION $path] ne "MaxDelay Path 10.000ns -datapath_only"} {
                error "Missing 10ns audio propagation bound: $port"
            }
        }
    }
    puts "PTROCOS AUDIO ELECTRICAL PASS: A11 OBUFT I=GND, D12 amplifier enable"
}
foreach {clock_pin expected_period} {cpu_clock/O 10.000 reference_clock/O 5.000 pixel_clock/O 39.682540} {
    set clocks [get_clocks -of_objects [get_pins $clock_pin]]
    if {[llength $clocks]!=1 || abs([get_property PERIOD $clocks]-$expected_period)>0.001} {
        error "Incorrect implemented clock at $clock_pin: $clocks, expected ${expected_period}ns"
    }
    puts "PTROCOS CLOCK VERIFIED: $clock_pin [get_property PERIOD $clocks] ns"
}
foreach pattern {
    {.*ddr_cdc/request_sync_reg\[0\]$}
    {.*ddr_cdc/completion_sync_reg\[0\]$}
    {.*ddr_cdc/payload_(we|addr|data|strobes)_reg(\[[0-9]+\])?$}
    {.*ddr_cdc/target_(we|addr|wdata|wstrb)_reg(\[[0-9]+\])?$}
    {.*ddr_cdc/response_(data|error)_reg(\[[0-9]+\])?$}
    {.*ddr_cdc/source_(rdata|error)_reg(\[[0-9]+\])?$}
    {.*(cpu|ui)_reset_sync_reg\[[01]\]$}
    {.*pixel_reset_sync_reg\[[01]\]$}
    {.*text_display/register_cdc/request_sync_reg\[0\]$}
    {.*text_display/register_cdc/completion_sync_reg\[0\]$}
    {.*text_display/register_cdc/payload_(we|addr|data|strobes)_reg(\[[0-9]+\])?$}
    {.*text_display/register_cdc/target_(we|addr|wdata|wstrb)_reg(\[[0-9]+\])?$}
    {.*text_display/register_cdc/response_data_reg(\[[0-9]+\])?$}
    {.*text_display/register_cdc/source_rdata_reg(\[[0-9]+\])?$}
    {.*keyboard/(clock|data)_sync_reg\[0\]$}
    {.*soc/sd/(miso|detect)_sync_reg\[0\]$}
} {
    if {![llength [get_cells -hier -quiet -regexp $pattern]]} {
        error "Missing mailbox constraint endpoint: $pattern"
    }
}
set graphics_mailboxes [list {.*graphics/register_cdc} {.*graphics/frame_cdc}]
for {set bank 0} {$bank<4} {incr bank} {
    lappend graphics_mailboxes [format {.*graphics/row_cdc\[%d\]\.mailbox} $bank]
}
foreach mailbox $graphics_mailboxes {
    foreach suffix {
        {request_sync_reg\[0\]$} {completion_sync_reg\[0\]$}
        {payload_(we|addr|data|strobes)_reg(\[[0-9]+\])?(_replica(_[0-9]+)?)?$}
        {target_(we|addr|wdata|wstrb)_reg(\[[0-9]+\])?(_replica(_[0-9]+)?)?$}
        {response_(data|error)_reg(\[[0-9]+\])?(_replica(_[0-9]+)?)?$}
        {source_(rdata|error)_reg(\[[0-9]+\])?(_replica(_[0-9]+)?)?$}
    } {
        if {![llength [get_cells -hier -quiet -regexp "$mailbox/$suffix"]]} {
            error "Missing graphics constraint endpoint: $mailbox/$suffix"
        }
    }
    foreach {from_pattern to_pattern} {
        {payload_(we|addr|data|strobes)} {target_(we|addr|wdata|wstrb)}
        {response_(data|error)} {source_(rdata|error)}
    } {
        set from [get_cells -hier -quiet -regexp [format {%s/%s_reg(\[[0-9]+\])?(_replica(_[0-9]+)?)?$} $mailbox $from_pattern]]
        set to [get_cells -hier -quiet -regexp [format {%s/%s_reg(\[[0-9]+\])?(_replica(_[0-9]+)?)?$} $mailbox $to_pattern]]
        set paths [get_timing_paths -quiet -from $from -to $to -delay_type max -max_paths 1000]
        if {![llength $paths]} {error "No timed graphics payload paths: $mailbox/$from_pattern"}
        foreach path $paths {
            if {[get_property EXCEPTION $path] ne "MaxDelay Path 10.000ns -datapath_only"} {
                error "Unbounded graphics CDC payload: [get_property NAME $path]"
            }
        }
        puts "PTROCOS GRAPHICS CDC COVERAGE: $mailbox/$from_pattern [llength $paths] timed endpoints, 10ns datapath bounds"
    }
    foreach sync {request completion} {
        set first [get_cells -hier -quiet -regexp [format {%s/%s_sync_reg\[0\]$} $mailbox $sync]]
        set first_d [get_pins -of_objects $first -filter {REF_PIN_NAME == D}]
        set toggle_paths [get_timing_paths -quiet -to $first_d -delay_type max -max_paths 1000]
        if {![llength $toggle_paths]} {error "Missing clocked graphics toggle path: $mailbox/$sync"}
        foreach path $toggle_paths {
            if {[get_property EXCEPTION $path] ne "False Path"} {
                error "Uncut graphics toggle synchronizer: $mailbox/$sync"
            }
        }
    }
}
if {[llength [get_cells -hier -quiet -regexp {.*graphics/blank_sync_reg\[0\]$}]]!=1} {
    error "Missing graphics swap-window constraint endpoint"
}
if {[llength [get_cells -hier -quiet -regexp {.*soc/sd/(miso|detect)_sync_reg\[0\]$}]]!=2} {
    error "Missing SD input synchronizers"
}
set preliminary [get_timing_paths -quiet -delay_type max -max_paths 1]
if {[llength $preliminary] && [get_property SLACK $preliminary]>=-0.500 &&
    [get_property SLACK $preliminary]<0.100} {
    if {[file tail $out] eq "ptrocos_media_vivado"} {
        # Physical optimization otherwise ignores positive slack below our
        # acceptance margin. Optimize against a tighter target, then restore
        # the normal clock uncertainty before reporting or emitting the bit.
        set_clock_uncertainty -setup 0.150 [get_clocks sys_clk]
        phys_opt_design -placement_opt -routing_opt
        route_design -directive Explore
        set_clock_uncertainty -setup 0.000 [get_clocks sys_clk]
    } else {
        phys_opt_design -directive AggressiveExplore
        route_design -directive NoTimingRelaxation
    }
}
write_checkpoint -force [file join $out ptrocos_routed.dcp]
report_timing_summary -delay_type min_max -report_unconstrained -check_timing_verbose -max_paths 20 -file [file join $reports timing_summary.rpt]
set timing_file [open [file join $reports timing_summary.rpt] r]
set timing_text [read $timing_file]
close $timing_file
if {![regexp -line {^\s+(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+\d+\s+\d+\s+(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+\d+\s+\d+\s+(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+\d+\s+\d+\s*$} \
    $timing_text all wns tns whs ths wpws tpws]} {
    error "Cannot parse routed timing summary acceptance fields"
}
if {$wns<0.100 || $tns!=0 || $whs<0 || $ths!=0 || $wpws<0 || $tpws!=0} {
    error "PtrocOS timing margin failed: WNS=$wns TNS=$tns WHS=$whs THS=$ths WPWS=$wpws TPWS=$tpws"
}
report_utilization -hierarchical -file [file join $reports utilization.rpt]
report_clock_utilization -file [file join $reports clocks.rpt]
report_clock_interaction -file [file join $reports clock_interaction.rpt]
report_cdc -details -file [file join $reports cdc.rpt]
report_exceptions -coverage -file [file join $reports exceptions.rpt]
check_timing -verbose -file [file join $reports check_timing.rpt]
report_drc -name ptrocos_drc -file [file join $reports drc.rpt]
report_methodology -file [file join $reports methodology.rpt]
source [file join $script_dir check_routed_timing.tcl]
set blocking {}
foreach violation [get_drc_violations -quiet] {
    if {[get_property SEVERITY $violation] in {Error {Critical Warning}}} {
        lappend blocking "[get_property ID $violation] ([get_property SEVERITY $violation])"
    }
}
if {[llength $blocking]} { error "Blocking DRC: $blocking" }
puts "PTROCOS ROUTED TIMING/DRC PASS"
