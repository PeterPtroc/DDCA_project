"""Verify uncached SoC measurements and estimate reuse from completed DDR addresses.

Cache replay predicts addresses only. It does not implement a cache, prove DMA
coherence, or model refill cycles; its hit rate is not a measured speedup.
"""
import csv
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'build/ptrocos_perf'
NAMES = ('measurement_overhead', 'register_loop', 'rom_read_1k_x4',
         'bram_read_1k_x4', 'ddr_read_1k_x4', 'ddr_stream_4k',
         'ddr_store_1k', 'ddr_pointer_chase_1k_x4', 'ddr_read_with_dma')
SUMS = (0, 523776, 2222592, 2222592, 2222592, 8907264, 256, 130560, 2222592)

def text(path):
    raw = path.read_bytes()
    return raw.decode('utf-16' if raw[:2] in (b'\xff\xfe', b'\xfe\xff') else 'utf-8-sig')

def replay(rows, capacity, line_bytes=16):
    tags = [None] * (capacity // line_bytes)
    hits = misses = stores = 0
    for row in rows:
        line = int(row['address'], 16) // line_bytes
        slot = line % len(tags)
        if int(row['write']):
            # Write-through, no write allocation. Existing data would be updated.
            stores += 1
        elif tags[slot] == line:
            hits += 1
        else:
            misses += 1
            tags[slot] = line
    return {'capacity_bytes': capacity, 'line_bytes': line_bytes,
            'policy': 'direct mapped, read allocation, write-through/no-write-allocate',
            'cold_at_case_start': True, 'read_hits': hits, 'read_misses': misses,
            'stores': stores, 'read_hit_fraction': hits / (hits + misses) if hits + misses else None}

def verify_style(style):
    log = text(OUT / f'runtime.style{style}.log')
    assert f'PTROCOS PERF SOC PASS style={style}' in log
    assert not re.search(r'Fatal:|FATAL_ERROR', log)
    uart = text(OUT / f'uart.style{style}.log')
    assert 'PTROCOS PERF FIRMWARE PASS' in uart
    firmware = re.findall(r'PERF case=([0-9a-f]{8}) cycles=([0-9a-f]{8}) retired=([0-9a-f]{8}) checksum=([0-9a-f]{8})', uart)
    assert len(firmware) == 9
    with (OUT / f'metrics.style{style}.csv').open(encoding='utf-8') as file:
        metrics = [{k: int(v) for k, v in row.items()} for row in csv.DictReader(file)]
    with (OUT / f'trace.style{style}.csv').open(encoding='utf-8') as file:
        trace = list(csv.DictReader(file))
    assert len(metrics) == 9
    cases = []
    for phase, (row, report) in enumerate(zip(metrics, firmware)):
        reported_phase, cycles, retired, checksum = map(lambda v: int(v, 16), report)
        assert row['phase'] == reported_phase == phase and checksum == SUMS[phase]
        assert cycles > 0 and retired > 0
        assert abs(row['cycles'] - cycles) < 100 and abs(row['retired'] - retired) < 100
        assert row['cycles'] >= row['bus_wait'] >= row['ddr_wait']
        accesses = [item for item in trace if int(item['phase']) == phase]
        if phase in (4, 8): addresses = [0x80000000 + 4 * (i % 256) for i in range(1024)]
        elif phase == 5: addresses = [0x80000000 + 4 * i for i in range(1024)]
        elif phase == 6: addresses = [0x80000000 + 4 * i for i in range(256)]
        elif phase == 7: addresses = [0x80000000 + 4 * ((37 * i) % 256) for i in range(1024)]
        else: addresses = []
        assert [int(item['address'], 16) for item in accesses] == addresses, (style, phase)
        assert all(int(item['write']) == int(phase == 6) for item in accesses)
        assert row['ddr_reads'] + row['ddr_writes'] == len(addresses)
        if phase < 4: assert row['bus_wait'] == row['ddr_wait'] == 0
        if phase == 8: assert row['dma_reads'] == row['dma_writes'] == 256
        cases.append({'name': NAMES[phase], **row, 'csr_cycles': cycles,
                      'csr_retired': retired, 'checksum': checksum,
                      # Testbench counts use the same begin/end window. CSR
                      # reads have staggered windows, especially for empty case.
                      'cycles_per_retired': row['cycles'] / row['retired'],
                      'ddr_wait_fraction': row['ddr_wait'] / row['cycles'],
                      'cache_address_replay': [replay(accesses, size) for size in (1024, 4096)]})
    assert sum(row['ddr_wait'] for row in metrics) > 0
    return {'style': style, 'cases': cases}

def main():
    styles = [verify_style(style) for style in (0, 1)]
    result = {'status': 'verified_uncached_soc_measurements', 'styles': styles,
              'CPU_Hz': 100000000, 'UI_clock_period_ns': 12.307,
              'instruction_source': 'existing single-cycle synchronous BRAM ROM',
              'instruction_external_wait_interface': False,
              'memory_model': 'full-address sparse AXI memory with independent AW/W/R/B delays',
              'real_board_performance_measured': False,
              'cache_implemented': False,
              'limits': ['Bare-metal microbenchmarks; no FreeRTOS/SD or VGA load in these measurements',
                         'AXI latency model is not a measurement of real MIG or card throughput',
                         'Address replay has cold start per case and models no refill latency',
                         'Address replay does not prove DMA coherence or MMIO ordering',
                         'load_use and m_wait columns are raw signal levels and may overlap bus_wait']}
    (OUT / 'measurements.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print('PTROCOS PERF ANALYSIS PASS styles=2 phases=18 independent-address-sequences CSR-checksums')
    for style in styles:
        print('style=' + str(style['style']))
        for case in style['cases']:
            print(f"  {case['name']}: cycles={case['csr_cycles']} retired={case['csr_retired']} DDRwait={case['ddr_wait_fraction']:.3%}")

if __name__ == '__main__':
    main()
