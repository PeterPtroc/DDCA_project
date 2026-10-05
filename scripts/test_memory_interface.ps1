param([string]$VivadoBin = 'D:\xilinx\Vivado\2024.2\bin')
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
$Python = (Get-Command python.exe -ErrorAction Stop).Source
$Xvlog = Join-Path $VivadoBin 'xvlog.bat'
$Xelab = Join-Path $VivadoBin 'xelab.bat'
$Xsim = Join-Path $VivadoBin 'xsim.bat'
function Invoke-Checked {
    param([string]$Command, [string[]]$Arguments)
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Command failed: $LASTEXITCODE" }
}
function Invoke-Simulation {
    param([string]$Top, [string]$Marker, [string]$Flag = '')
    $snapshot = "${Top}_memory_sim"
    Invoke-Checked $Xelab @('--nolog', "ptrocos_mem.$Top", '-s', $snapshot, '-debug', 'typical')
    $arguments = @($snapshot, '--nolog', '-runall')
    if ($Flag) { $arguments += @('--testplusarg', $Flag) }
    $output = & $Xsim @arguments 2>&1
    $exitCode = $LASTEXITCODE
    $output | ForEach-Object { Write-Host $_ }
    if ($exitCode -ne 0 -or ($output -join "`n") -match 'Fatal:' -or
        ($output -join "`n") -notmatch [regex]::Escape($Marker)) {
        throw "Simulation $Top failed or missing marker $Marker"
    }
}
Invoke-Checked 'git' @('diff', '--exit-code', '191da2f0ea6485f6d6bb140418bf774b669e792a', '--',
    'src/rtl/cpu/rv32_core.v', 'src/rtl/cpu/rv32im_core.v', 'src/rtl/cpu/rv32im_decoder.v',
    'src/rtl/cpu/rv32m_unit.v', 'src/rtl/cpu/decoder.v', 'src/rtl/top/soc_top.v',
    'src/rtl/top/nexys_a7_top.v', 'scripts/create_vivado_project.tcl', 'scripts/test.ps1')
Invoke-Checked $Python @('sw/tools/gen_rv32m_tests.py', 'build/rv32m')
Invoke-Checked $Python @('sw/tools/rv32m_ref.py', 'build/rv32m/isa.hex', 'build/rv32m/isa.reference.csv')
$sources = @('alu', 'crc16_unit', 'decoder', 'hazard_unit', 'imm_gen', 'regfile',
             'rv32m_unit', 'rv32im_decoder', 'rv32im_mem_core') | ForEach-Object {
    (Resolve-Path -LiteralPath "src/rtl/cpu/$_.v").Path
}
$sources += @('src/rtl/bus/word_bus_arbiter.v', 'src/rtl/memory/word_bus_cdc.v',
              'src/rtl/memory/ddr2_axi_word_bridge.v', 'src/rtl/peripheral/dma_copy.v',
              'src/sim/tb_rv32m_wait_trace.v', 'src/sim/tb_rv32m_wait_irq.v',
              'src/sim/tb_memory_faults.v', 'src/sim/tb_ddr2_axi_word.v', 'src/sim/tb_memory_fabric.v')
Invoke-Checked $Xvlog (@('--nolog', '-work', 'ptrocos_mem') + $sources)
Invoke-Simulation 'tb_rv32m_wait_trace' 'RTL TRACE PASS' 'RV32M_TEST'
Invoke-Checked $Python @('sw/tools/diff_trace.py', 'build/rv32m/isa.reference.csv',
                        'build/rv32m/isa.wait.rtl.csv', '--name', 'memory-wait-style0')
Invoke-Simulation 'tb_rv32m_wait_trace_alt' 'RTL TRACE PASS' 'RV32M_TEST'
Invoke-Checked $Python @('sw/tools/diff_trace.py', 'build/rv32m/isa.reference.csv',
                        'build/rv32m/isa.wait.alt.rtl.csv', '--name', 'memory-wait-style1')
Invoke-Simulation 'tb_rv32m_wait_irq' 'RV32M WAIT IRQ PASS'
Invoke-Simulation 'tb_memory_faults' 'MEMORY FAULT PASS'
Invoke-Simulation 'tb_ddr2_axi_word' 'DDR2 AXI WORD PASS'
Invoke-Simulation 'tb_memory_fabric' 'MEMORY FABRIC PASS'
Write-Host 'EXTERNAL MEMORY INTERFACE TEST PASS (MIG/board integration remains separate)'
