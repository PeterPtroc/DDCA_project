# Read-only inventory; no programming or flash writes.
open_hw_manager
connect_hw_server -url TCP:localhost:31234 -allow_non_jtag
set targets [get_hw_targets -quiet]
puts "PTROCOS JTAG TARGETS: $targets"
foreach target $targets {
    if {[catch {open_hw_target $target} message]} {
        puts "PTROCOS JTAG OPEN FAILED: $target: $message"
        continue
    }
    foreach device [get_hw_devices -quiet] {
        puts "PTROCOS JTAG DEVICE: [get_property NAME $device] PART=[get_property PART $device] TARGET=$target"
    }
    close_hw_target
}
disconnect_hw_server
close_hw_manager
