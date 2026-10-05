param([string]$VivadoBin = 'D:\xilinx\Vivado\2024.2\bin')
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$Root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $Root
$Python = (Get-Command python.exe -ErrorAction Stop).Source
$Xvlog = Join-Path $VivadoBin 'xvlog.bat'
$Xelab = Join-Path $VivadoBin 'xelab.bat'
$Xsim = Join-Path $VivadoBin 'xsim.bat'
foreach ($tool in @($Xvlog, $Xelab, $Xsim)) {
    if (-not (Test-Path -LiteralPath $tool)) { throw "Missing XSim tool: $tool" }
}
function Invoke-Checked {
    param([string]$Command, [string[]]$Arguments)
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Command failed: $LASTEXITCODE" }
}
function Invoke-Simulation {
    param([string]$Top, [string]$Marker, [string]$Flag = '')
    $snapshot = "${Top}_sim"
    Invoke-Checked $Xelab @('--nolog', "rv32m.$Top", '-s', $snapshot, '-debug', 'typical')
    $arguments = @($snapshot, '--nolog', '-runall')
    if ($Flag) { $arguments += @('--testplusarg', $Flag) }
    $output = & $Xsim @arguments 2>&1
    $exitCode = $LASTEXITCODE
    $output | ForEach-Object { Write-Host $_ }
    if ($exitCode -ne 0 -or ($output -join "`n") -notmatch [regex]::Escape($Marker)) {
        throw "Simulation $Top failed or missing marker $Marker"
    }
}

# Protect the known-good implementation and its production integration.
$baseline = '80cc06f144e8c954c662490dbeac25e489bfda8d'
$frozen = @('src/rtl/cpu/rv32_core.v', 'src/rtl/cpu/decoder.v',
            'src/rtl/cpu/alu.v', 'src/rtl/cpu/hazard_unit.v',
            'src/rtl/cpu/forwarding_unit.v', 'src/rtl/cpu/imm_gen.v',
            'src/rtl/cpu/regfile.v', 'src/rtl/cpu/crc16_unit.v',
            'src/rtl/top/soc_top.v', 'src/rtl/top/nexys_a7_top.v',
            'scripts/create_vivado_project.tcl', 'scripts/test.ps1')
Invoke-Checked 'git' (@('diff', '--exit-code', $baseline, '--') + $frozen)
Invoke-Checked $Python @('-m', 'unittest', 'discover', '-s', 'sw/tools', '-p', 'test_rv32m_ref.py')
Invoke-Checked $Python @('sw/tools/gen_rv32m_tests.py', 'build/rv32m')
Invoke-Checked $Python @('sw/tools/rv32m_ref.py', 'build/rv32m/isa.hex', 'build/rv32m/isa.reference.csv')

$sources = @('alu', 'crc16_unit', 'decoder', 'hazard_unit', 'imm_gen', 'regfile',
             'rv32m_unit', 'rv32im_decoder', 'rv32im_core') | ForEach-Object {
    (Resolve-Path -LiteralPath "src/rtl/cpu/$_.v").Path
}
$benches = @('src/sim/tb_rv32m_unit.v', 'src/sim/tb_rv32m_trace.v',
             'src/sim/tb_rv32m_irq.v', 'src/sim/tb_rv32m_control.v')
Invoke-Checked $Xvlog (@('--nolog', '-work', 'rv32m') + $sources + $benches)
Invoke-Simulation 'tb_rv32m_unit' 'RV32M UNIT PASS'
Invoke-Simulation 'tb_rv32m_trace' 'RTL TRACE PASS' 'RV32M_TEST'
Invoke-Checked $Python @('sw/tools/diff_trace.py', 'build/rv32m/isa.reference.csv',
                        'build/rv32m/isa.rtl.csv', '--name', 'rv32m-style0')
Invoke-Simulation 'tb_rv32m_trace_alt' 'RTL TRACE PASS' 'RV32M_TEST'
Invoke-Checked $Python @('sw/tools/diff_trace.py', 'build/rv32m/isa.reference.csv',
                        'build/rv32m/isa.alt.rtl.csv', '--name', 'rv32m-style1')
Invoke-Simulation 'tb_rv32m_irq' 'RV32M IRQ PASS'
Invoke-Simulation 'tb_rv32m_control' 'RV32M CONTROL PASS'

# Reuse the established I/CRC and precise-trap checks against the new core.
New-Item -ItemType Directory -Path 'build/hex', 'build/trace', 'build/benchmark' -Force | Out-Null
foreach ($name in @('isa_test', 'hazard_test', 'crc_test', 'machine_test')) {
    Invoke-Checked $Python @('sw/tools/rv32asm.py', "sw/firmware/$name.S", "build/hex/$name.hex")
}
foreach ($name in @('isa_test', 'hazard_test', 'crc_test')) {
    Invoke-Simulation 'tb_rv32m_trace' 'RTL TRACE PASS' ($name.ToUpperInvariant())
    Invoke-Checked $Python @('sw/tools/rv32_ref.py', "build/hex/$name.hex", "build/rv32m/$name.reference.csv")
    Invoke-Checked $Python @('sw/tools/diff_trace.py', "build/rv32m/$name.reference.csv",
                            "build/trace/$name.rtl.csv", '--name', "rv32im-$name")
}
foreach ($name in @('machine_mode', 'precise_irq')) {
    $source = Get-Content -LiteralPath "src/sim/tb_$name.v" -Raw
    $source = $source.Replace('rv32_core', 'rv32im_core').Replace("tb_$name", "tb_rv32m_$name")
    $source = $source.Replace('precise_irq_runner', 'rv32m_precise_irq_runner')
    if ($name -eq 'machine_mode') {
        $firmware = (Get-Content -LiteralPath 'sw/firmware/machine_test.S' -Raw).Replace('0x40000100', '0x40001100')
        Set-Content -LiteralPath 'build/rv32m/machine_test.S' -Value $firmware -Encoding ascii
        Invoke-Checked $Python @('sw/tools/rv32asm.py', 'build/rv32m/machine_test.S', 'build/rv32m/machine.hex')
        $source = $source.Replace('build/hex/machine_test.hex', 'build/rv32m/machine.hex')
    }
    $generated = "build/rv32m/tb_rv32m_$name.v"
    Set-Content -LiteralPath $generated -Value $source -Encoding ascii
    Invoke-Checked $Xvlog @('--nolog', '-work', 'rv32m', 'src/rtl/peripheral/clint.v', $generated)
    $marker = if ($name -eq 'machine_mode') { 'MACHINE MODE PASS' } else { 'PRECISE IRQ PASS' }
    Invoke-Simulation "tb_rv32m_$name" $marker
}
Write-Host 'RV32M INDEPENDENT ISA TEST PASS; frozen CPU baseline unchanged'
