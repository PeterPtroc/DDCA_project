"""Resolve call/return PCs from the compiled kernel, for independent RTL checks."""
from pathlib import Path
import re
import subprocess
import argparse
p=argparse.ArgumentParser();p.add_argument('--toolchain-prefix',required=True);a=p.parse_args()
out=Path('build/ptrocos_elf')
dump=subprocess.check_output([a.toolchain_prefix+'-objdump.exe','-d',str(out/'ptrocos_elf.elf')],text=True)
start=re.search(r'^([0-9a-f]+) <ptrocos_app_call>:',dump,re.M)
abort=re.search(r'^([0-9a-f]+) <ptrocos_app_abort>:\n(.*?)(?=\n[0-9a-f]+ <|\Z)',dump,re.M|re.S)
assert start and abort
returns=re.findall(r'^\s+([0-9a-f]+):\s+00008067\s+ret\s*$',abort[2],re.M)
assert len(returns)==1
pcs=[int(start[1],16),int(returns[0],16)]
(out/'call-reference.hex').write_text('\n'.join(f'{x:08x}' for x in pcs)+'\n',encoding='ascii')
print('ELF CALL REFERENCE PASS call=%08x return=%08x'%tuple(pcs))
