PYTHON ?= python3
IVERILOG ?= iverilog
RTL := $(shell find src/rtl -name '*.v' | sort)
FW_DIR := sw/firmware
TOOL_DIR := sw/tools
HEX_DIR := build/hex
OBJ_DIR := build/obj

.PHONY: help asm lint unit test clean
help:
	@printf '%s\n' 'make asm   Assemble firmware' 'make lint  Compile RTL tops with Icarus' 'make unit  Alias for lint' 'make test  Build-only smoke checks (no simulation)' 'make vivado Create Vivado project in build/vivado' 'make clean'

asm: $(HEX_DIR)/mvp.hex $(HEX_DIR)/isa_test.hex $(HEX_DIR)/hazard_test.hex $(HEX_DIR)/crc_test.hex
$(HEX_DIR)/%.hex: $(FW_DIR)/%.S $(TOOL_DIR)/rv32asm.py
	@mkdir -p $(HEX_DIR)
	$(PYTHON) $(TOOL_DIR)/rv32asm.py $< $@

lint:
	@mkdir -p $(OBJ_DIR)
	$(IVERILOG) -g2012 -s nexys_a7_top -o $(OBJ_DIR)/lint.out $(RTL)

unit: lint
test: asm lint
	@printf '%s\n' 'RTL compile completed; runtime simulation intentionally not run.'

vivado:
	vivado -mode batch -source scripts/create_vivado_project.tcl

clean:
	rm -rf build/hex build/obj build/vivado
