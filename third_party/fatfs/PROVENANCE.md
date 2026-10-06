# FatFs R0.16 with official patches 1 and 2

Author: ChaN. Source: <https://elm-chan.org/fsw/ff/>.

The upstream license permits source and binary redistribution and modification,
provided the copyright notice, redistribution condition and disclaimer remain.
The complete notice is retained at the beginning of each upstream source file.

`upstream/` preserves the original R0.16 source bytes. Active `ff.c` applies the
official patches in order; its line endings are normalized to LF. Active headers
and `ffunicode.c` retain their original bytes. The project configuration lives in
`sw/ptrocos/storage/ffconf.h`; upstream's example configuration is not active.

Reproduce with `python sw/tools/vendor_fatfs.py`, using these official downloads:

| Download | SHA-256 |
| --- | --- |
| <https://elm-chan.org/fsw/ff/arc/ff16.zip> | `99f7dc1f7e095356e4a9e3dbe29959090d8b948afe2bbc5441e52fdf4b85449e` |
| <https://elm-chan.org/fsw/ff/patch/ff16p1.diff> | `7996ddc3135f3d534a8153f7d75d587030e5c8551b003c3b7ee823ffb7fc64bf` |
| <https://elm-chan.org/fsw/ff/patch/ff16p2.diff> | `5cd39f1fc299f0f1dec9fa1ce544dc0bc048b2f6eb3b8161476ed20f9cf1e290` |

The vendor script checks all archive/patch hashes and patch contexts before
writing files. Patches include upstream volume-size and malformed-filesystem
validation fixes. Native tests include the malformed FAT-size regression.
