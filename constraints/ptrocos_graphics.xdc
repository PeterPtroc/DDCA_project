# Held-payload CDC: source data remains stable until two toggle stages and ACK.
# Use only standard XDC commands. Endpoint existence is checked by the timing gate.
# Never cut whole clock domains. All local paths and MIG clocks stay timed.

# .*graphics/register_cdc
set gfx_req [get_cells -hier -regexp {.*graphics/register_cdc/request_sync_reg\[0\]$}]
set gfx_ack [get_cells -hier -regexp {.*graphics/register_cdc/completion_sync_reg\[0\]$}]
set_false_path -to [get_pins -of_objects $gfx_req -filter {REF_PIN_NAME == D}]
set_false_path -to [get_pins -of_objects $gfx_ack -filter {REF_PIN_NAME == D}]
set gfx_payload [get_cells -hier -regexp {.*graphics/register_cdc/payload_(we|addr|data|strobes)_reg(\[[0-9]+\])?(_replica(_[0-9]+)?)?$}]
set gfx_capture [get_cells -hier -regexp {.*graphics/register_cdc/target_(we|addr|wdata|wstrb)_reg(\[[0-9]+\])?(_replica(_[0-9]+)?)?$}]
set gfx_reply [get_cells -hier -regexp {.*graphics/register_cdc/response_(data|error)_reg(\[[0-9]+\])?(_replica(_[0-9]+)?)?$}]
set gfx_return [get_cells -hier -regexp {.*graphics/register_cdc/source_(rdata|error)_reg(\[[0-9]+\])?(_replica(_[0-9]+)?)?$}]
set_max_delay -datapath_only 10.000 -from $gfx_payload -to $gfx_capture
set_max_delay -datapath_only 10.000 -from $gfx_reply -to $gfx_return
set_false_path -hold -from $gfx_payload -to $gfx_capture
set_false_path -hold -from $gfx_reply -to $gfx_return

# .*graphics/frame_cdc
set gfx_req [get_cells -hier -regexp {.*graphics/frame_cdc/request_sync_reg\[0\]$}]
set gfx_ack [get_cells -hier -regexp {.*graphics/frame_cdc/completion_sync_reg\[0\]$}]
set_false_path -to [get_pins -of_objects $gfx_req -filter {REF_PIN_NAME == D}]
set_false_path -to [get_pins -of_objects $gfx_ack -filter {REF_PIN_NAME == D}]
set gfx_payload [get_cells -hier -regexp {.*graphics/frame_cdc/payload_(we|addr|data|strobes)_reg(\[[0-9]+\])?(_replica(_[0-9]+)?)?$}]
set gfx_capture [get_cells -hier -regexp {.*graphics/frame_cdc/target_(we|addr|wdata|wstrb)_reg(\[[0-9]+\])?(_replica(_[0-9]+)?)?$}]
set gfx_reply [get_cells -hier -regexp {.*graphics/frame_cdc/response_data_reg(\[[0-9]+\])?(_replica(_[0-9]+)?)?$}]
set gfx_return [get_cells -hier -regexp {.*graphics/frame_cdc/source_(rdata|error)_reg(\[[0-9]+\])?(_replica(_[0-9]+)?)?$}]
set_max_delay -datapath_only 10.000 -from $gfx_payload -to $gfx_capture
set_max_delay -datapath_only 10.000 -from $gfx_reply -to $gfx_return
set_false_path -hold -from $gfx_payload -to $gfx_capture
set_false_path -hold -from $gfx_reply -to $gfx_return

# .*graphics/row_cdc\[0\]\.mailbox
set gfx_req [get_cells -hier -regexp {.*graphics/row_cdc\[0\]\.mailbox/request_sync_reg\[0\]$}]
set gfx_ack [get_cells -hier -regexp {.*graphics/row_cdc\[0\]\.mailbox/completion_sync_reg\[0\]$}]
set_false_path -to [get_pins -of_objects $gfx_req -filter {REF_PIN_NAME == D}]
set_false_path -to [get_pins -of_objects $gfx_ack -filter {REF_PIN_NAME == D}]
set gfx_payload [get_cells -hier -regexp {.*graphics/row_cdc\[0\]\.mailbox/payload_(we|addr|data|strobes)_reg(\[[0-9]+\])?(_replica(_[0-9]+)?)?$}]
set gfx_capture [get_cells -hier -regexp {.*graphics/row_cdc\[0\]\.mailbox/target_(we|addr|wdata|wstrb)_reg(\[[0-9]+\])?(_replica(_[0-9]+)?)?$}]
set gfx_reply [get_cells -hier -regexp {.*graphics/row_cdc\[0\]\.mailbox/response_error_reg(\[[0-9]+\])?(_replica(_[0-9]+)?)?$}]
set gfx_return [get_cells -hier -regexp {.*graphics/row_cdc\[0\]\.mailbox/source_(rdata|error)_reg(\[[0-9]+\])?(_replica(_[0-9]+)?)?$}]
set_max_delay -datapath_only 10.000 -from $gfx_payload -to $gfx_capture
set_max_delay -datapath_only 10.000 -from $gfx_reply -to $gfx_return
set_false_path -hold -from $gfx_payload -to $gfx_capture
set_false_path -hold -from $gfx_reply -to $gfx_return

# .*graphics/row_cdc\[1\]\.mailbox
set gfx_req [get_cells -hier -regexp {.*graphics/row_cdc\[1\]\.mailbox/request_sync_reg\[0\]$}]
set gfx_ack [get_cells -hier -regexp {.*graphics/row_cdc\[1\]\.mailbox/completion_sync_reg\[0\]$}]
set_false_path -to [get_pins -of_objects $gfx_req -filter {REF_PIN_NAME == D}]
set_false_path -to [get_pins -of_objects $gfx_ack -filter {REF_PIN_NAME == D}]
set gfx_payload [get_cells -hier -regexp {.*graphics/row_cdc\[1\]\.mailbox/payload_(we|addr|data|strobes)_reg(\[[0-9]+\])?(_replica(_[0-9]+)?)?$}]
set gfx_capture [get_cells -hier -regexp {.*graphics/row_cdc\[1\]\.mailbox/target_(we|addr|wdata|wstrb)_reg(\[[0-9]+\])?(_replica(_[0-9]+)?)?$}]
set gfx_reply [get_cells -hier -regexp {.*graphics/row_cdc\[1\]\.mailbox/response_error_reg(\[[0-9]+\])?(_replica(_[0-9]+)?)?$}]
set gfx_return [get_cells -hier -regexp {.*graphics/row_cdc\[1\]\.mailbox/source_(rdata|error)_reg(\[[0-9]+\])?(_replica(_[0-9]+)?)?$}]
set_max_delay -datapath_only 10.000 -from $gfx_payload -to $gfx_capture
set_max_delay -datapath_only 10.000 -from $gfx_reply -to $gfx_return
set_false_path -hold -from $gfx_payload -to $gfx_capture
set_false_path -hold -from $gfx_reply -to $gfx_return

# .*graphics/row_cdc\[2\]\.mailbox
set gfx_req [get_cells -hier -regexp {.*graphics/row_cdc\[2\]\.mailbox/request_sync_reg\[0\]$}]
set gfx_ack [get_cells -hier -regexp {.*graphics/row_cdc\[2\]\.mailbox/completion_sync_reg\[0\]$}]
set_false_path -to [get_pins -of_objects $gfx_req -filter {REF_PIN_NAME == D}]
set_false_path -to [get_pins -of_objects $gfx_ack -filter {REF_PIN_NAME == D}]
set gfx_payload [get_cells -hier -regexp {.*graphics/row_cdc\[2\]\.mailbox/payload_(we|addr|data|strobes)_reg(\[[0-9]+\])?(_replica(_[0-9]+)?)?$}]
set gfx_capture [get_cells -hier -regexp {.*graphics/row_cdc\[2\]\.mailbox/target_(we|addr|wdata|wstrb)_reg(\[[0-9]+\])?(_replica(_[0-9]+)?)?$}]
set gfx_reply [get_cells -hier -regexp {.*graphics/row_cdc\[2\]\.mailbox/response_error_reg(\[[0-9]+\])?(_replica(_[0-9]+)?)?$}]
set gfx_return [get_cells -hier -regexp {.*graphics/row_cdc\[2\]\.mailbox/source_(rdata|error)_reg(\[[0-9]+\])?(_replica(_[0-9]+)?)?$}]
set_max_delay -datapath_only 10.000 -from $gfx_payload -to $gfx_capture
set_max_delay -datapath_only 10.000 -from $gfx_reply -to $gfx_return
set_false_path -hold -from $gfx_payload -to $gfx_capture
set_false_path -hold -from $gfx_reply -to $gfx_return

# .*graphics/row_cdc\[3\]\.mailbox
set gfx_req [get_cells -hier -regexp {.*graphics/row_cdc\[3\]\.mailbox/request_sync_reg\[0\]$}]
set gfx_ack [get_cells -hier -regexp {.*graphics/row_cdc\[3\]\.mailbox/completion_sync_reg\[0\]$}]
set_false_path -to [get_pins -of_objects $gfx_req -filter {REF_PIN_NAME == D}]
set_false_path -to [get_pins -of_objects $gfx_ack -filter {REF_PIN_NAME == D}]
set gfx_payload [get_cells -hier -regexp {.*graphics/row_cdc\[3\]\.mailbox/payload_(we|addr|data|strobes)_reg(\[[0-9]+\])?(_replica(_[0-9]+)?)?$}]
set gfx_capture [get_cells -hier -regexp {.*graphics/row_cdc\[3\]\.mailbox/target_(we|addr|wdata|wstrb)_reg(\[[0-9]+\])?(_replica(_[0-9]+)?)?$}]
set gfx_reply [get_cells -hier -regexp {.*graphics/row_cdc\[3\]\.mailbox/response_error_reg(\[[0-9]+\])?(_replica(_[0-9]+)?)?$}]
set gfx_return [get_cells -hier -regexp {.*graphics/row_cdc\[3\]\.mailbox/source_(rdata|error)_reg(\[[0-9]+\])?(_replica(_[0-9]+)?)?$}]
set_max_delay -datapath_only 10.000 -from $gfx_payload -to $gfx_capture
set_max_delay -datapath_only 10.000 -from $gfx_reply -to $gfx_return
set_false_path -hold -from $gfx_payload -to $gfx_capture
set_false_path -hold -from $gfx_reply -to $gfx_return

set gfx_window [get_cells -hier -regexp {.*graphics/blank_sync_reg\[0\]$}]
set_false_path -to [get_pins -of_objects $gfx_window -filter {REF_PIN_NAME == D}]
