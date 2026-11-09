{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/f4a03c008967841f2a0b3cb7c436fc6fc31671f6";

  outputs =
    { nixpkgs, ... }:
    let
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      # Compiles main.c with pkgsCross.avr's wrapped gcc, then records the
      # object's size and the prologue of mix().
      compile =
        pkgs: name: extraFlags:
        pkgs.runCommand name { nativeBuildInputs = [ pkgs.pkgsCross.avr.buildPackages.gcc ]; } ''
          avr-gcc -mmcu=atmega32u4 -Os ${extraFlags} -c ${./main.c} -o main.o
          {
            avr-size main.o
            avr-objdump -d main.o | sed -n '/<mix>:/,/movw/p'
          } > $out
        '';
    in
    {
      packages = forAllSystems (pkgs: {
        # pkgsCross.avr.buildPackages.gcc as the cc-wrapper ships it.
        repro = compile pkgs "repro" "";
        # The same compiler with GCC's default for -Os restored.
        baseline = compile pkgs "baseline" "-fomit-frame-pointer";
        # The flags the wrapper puts before the user's own.
        wrapper-flags = pkgs.runCommand "wrapper-flags" { } ''
          cp ${pkgs.pkgsCross.avr.buildPackages.gcc}/nix-support/cc-cflags-before $out
        '';
      });
    };
}
