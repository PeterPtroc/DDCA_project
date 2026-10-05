# Derive only clock ownership from the unchanged official board preset. The
# top provides a buffered 100 MHz system input and a separate 200 MHz reference.
set upstream [file join $root third_party digilent nexys-a7-100t-mig.prj]
set preset_file [open $upstream r]
set preset [read $preset_file]
close $preset_file
foreach original {{<SystemClock>Single-Ended</SystemClock>} {<UIExtraClocks>1</UIExtraClocks>}} {
    if {[string first $original $preset]<0} { error "Unexpected upstream MIG clock field: $original" }
}
set preset [string map [list {<SystemClock>Single-Ended</SystemClock>} {<SystemClock>No Buffer</SystemClock>} \
    {<UIExtraClocks>1</UIExtraClocks>} {<UIExtraClocks>0</UIExtraClocks>}] $preset]
set derived [file join $out ptrocos-mig.prj]
set preset_file [open $derived w]
fconfigure $preset_file -translation lf
puts -nonewline $preset_file $preset
close $preset_file
set_property CONFIG.XML_INPUT_FILE $derived [get_ips ptrocos_ddr2_mig]
generate_target all [get_ips ptrocos_ddr2_mig]
# Verify clock buffer ownership; actual 100/200 MHz frequencies are checked
# against the implemented clock objects by finalize_ptrocos_timing.tcl.
set generated [glob [file join $out *.gen sources_1 ip ptrocos_ddr2_mig ptrocos_ddr2_mig user_design rtl ptrocos_ddr2_mig_mig.v]]
set rtl_file [open $generated r]
set rtl [read $rtl_file]
close $rtl_file
foreach {name expected} {SYSCLK_TYPE NO_BUFFER REFCLK_TYPE NO_BUFFER UI_EXTRA_CLOCKS FALSE} {
    if {![regexp "parameter\\s+$name\\s*=\\s*\"$expected\"" $rtl]} {
        error "MIG generator did not accept $name=$expected"
    }
}
puts "PTROCOS MIG CLOCK OWNERSHIP VERIFIED: external system/reference buffers"
