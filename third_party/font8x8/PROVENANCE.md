# font8x8

Source: [dhepper/font8x8](https://github.com/dhepper/font8x8), commit `8e279d2d864e79128e96188a6b9526cfa3fbfef9`, retrieved 2026-10-06.

`font8x8_basic.h` and `README` are unchanged upstream files. The upstream author declares the font Public Domain and credits Daniel Hepper, Marcel Sondaar and the IBM VGA fonts. The original notice is retained in the header and README.

| File | SHA-256 |
| --- | --- |
| font8x8_basic.h | 49d8df366296b203ca3211bc0672cf2a762135bf12710735b6292756b19dffd5 |
| README | 885cc022fa9c844695b364e77e6a18ab2be74678a181827f1ce893071205cb65 |

`sw/tools/gen_text_font.py` generates `src/rtl/video/text_font_rom.v` from the header's 128 characters × 8 bytes. Bit 0 is the leftmost pixel. The renderer repeats each row twice for 8×16 text cells. No font download is needed during synthesis or simulation.
