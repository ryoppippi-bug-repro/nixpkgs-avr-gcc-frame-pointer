# avr-gcc from nixpkgs forces frame pointers and grows AVR firmware

Reproduction for ISSUE_LINK. nixpkgs `f4a03c008967841f2a0b3cb7c436fc6fc31671f6` (nixos-unstable), avr-gcc 16.2.0, Nix 2.34.9, tested on aarch64-darwin.

## Steps

```sh
nix build .#wrapper-flags && cat result   # -fno-omit-frame-pointer
nix build .#repro && cat result           # 142 bytes, mix() sets up Y as a frame pointer
nix build .#baseline && cat result        # 130 bytes, no frame pointer
```

## Details

`pkgsCross.avr.buildPackages.gcc` always compiles with `-fno-omit-frame-pointer`. The cc-wrapper writes it into `nix-support/cc-cflags-before` for every target except x86_32 and s390, and `hardeningDisable` does not remove it.

On AVR this makes functions that would not otherwise need a frame pointer save, load and restore the Y register pair (r28/r29). For `main.c`:

```c
#include <stdint.h>

uint32_t now(void);

uint32_t mix(uint32_t x, uint32_t y) {
    uint32_t t = now();
    return (x * t) ^ (y + now()) ^ t;
}
```

compiled with `avr-gcc -mmcu=atmega32u4 -Os -c main.c`, the object is 142 bytes instead of 130 (+9%).

In a real QMK keyboard firmware for an ATmega32u4 (Pro Micro), the whole image is 17,076 bytes with the wrapper as shipped (hardening already disabled) and 16,142 bytes without that flag: 934 bytes, 5.5% of the image, on a chip with 28,672 bytes of usable flash.

## Cause

`repro` (wrapper as shipped) against `baseline` (the same wrapper with `-fomit-frame-pointer` appended, which is GCC's default at `-O1` and above on AVR):

```
== repro                                  == baseline
text  142                                 text  130
  ...push r4 ... push r15                   ...push r4 ... push r15
  push r28                                  movw r8, r22
  push r29
  in   r28, 0x3d   ; SPL
  in   r29, 0x3e   ; SPH
  movw r8, r22
```

plus the matching epilogue.

## Analysis

`pkgs/build-support/cc-wrapper/default.nix` (read at master `113a81c0655f`) enables frame pointers unless `targetPlatform.isx86_32 || targetPlatform.isS390`:

```nix
enable_fp = !targetPlatform.isx86_32 && !targetPlatform.isS390;
```

This came from #399014 ("cc-wrapper: enable frame pointers by default"); s390 was excluded afterwards in #428446. The motivation (profiling and unwinding on hosted systems) does not apply to bare-metal microcontrollers such as AVR, where flash is a few tens of kilobytes, there is no unwinder, and Y is one of only three pointer registers.

A possible fix is to skip it for AVR as well (`&& !targetPlatform.isAvr`), or for embedded targets in general (`targetPlatform.parsed.kernel.name == "none"`). I have not patched cc-wrapper and rebuilt; I only confirmed that removing the line from `cc-cflags-before` (or appending `-fomit-frame-pointer`) gives the smaller code.

## How it was found

Building [QMK](https://github.com/qmk/qmk_firmware) firmware with `pkgs.qmk` (which propagates `pkgsCross.avr.buildPackages.gcc`) produced an image about 1 KB larger than QMK's own Docker toolchain. `NIX_DEBUG=1` showed the injected flag; removing it from `cc-cflags-before` recovered 934 bytes. QMK is not needed to reproduce it.

## Files

- `main.c`: one function that does not need a frame pointer.
- `flake.nix`: `repro` compiles it with the wrapper as shipped, `baseline` appends `-fomit-frame-pointer`, `wrapper-flags` prints the wrapper's `cc-cflags-before`.
