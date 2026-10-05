# word_bus_cdc is a one-entry bundled-data mailbox. Each payload remains held
# until its toggle has crossed two synchronizer stages and completion returns.
# Bound physical data delay to one 100 MHz cycle, before the toggle is observed.
# Do not cut entire clock domains: MIG timing and local datapaths remain timed.
set req_first [get_cells -hier -regexp {.*ddr_cdc/request_sync_reg\[0\]$}]
set ack_first [get_cells -hier -regexp {.*ddr_cdc/completion_sync_reg\[0\]$}]
set_false_path -to [get_pins -of_objects $req_first -filter {REF_PIN_NAME == D}]
set_false_path -to [get_pins -of_objects $ack_first -filter {REF_PIN_NAME == D}]
set request_payload [get_cells -hier -regexp {.*ddr_cdc/payload_(we|addr|data|strobes)_reg(\[[0-9]+\])?$}]
set request_capture [get_cells -hier -regexp {.*ddr_cdc/target_(we|addr|wdata|wstrb)_reg(\[[0-9]+\])?$}]
set response_payload [get_cells -hier -regexp {.*ddr_cdc/response_(data|error)_reg(\[[0-9]+\])?$}]
set response_capture [get_cells -hier -regexp {.*ddr_cdc/source_(rdata|error)_reg(\[[0-9]+\])?$}]
set_max_delay -datapath_only 10.000 -from $request_payload -to $request_capture
set_max_delay -datapath_only 10.000 -from $response_payload -to $response_capture
# Hold checks have no meaning between asynchronous bundled-data registers.
set_false_path -hold -from $request_payload -to $request_capture
set_false_path -hold -from $response_payload -to $response_capture
# The combined loss-of-lock/calibration reset asserts asynchronously. Only the
# reset-release synchronizer clears ignore recovery/removal. Release travels
# through two locally clocked stages; all downstream logic remains timed.
set reset_sync [get_cells -hier -regexp {.*(cpu|ui)_reset_sync_reg\[[01]\]$}]
set_false_path -to [get_pins -of_objects $reset_sync -filter {REF_PIN_NAME == CLR}]
