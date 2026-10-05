# Publish the same artifact after either GUI or batch bitstream generation.
set ddca_publish_root [file normalize [file join [file dirname [info script]] ..]]
# Vivado executes run hooks in the run directory; its child process need not
# expose the parent project's run objects.
set ddca_generated_bit [file join [pwd] nexys_a7_top.bit]
set ddca_published_bit [file join $ddca_publish_root build vivado rv32_realtime_scope.bit]
file copy -force $ddca_generated_bit $ddca_published_bit
puts "BITSTREAM PASS: $ddca_published_bit"
