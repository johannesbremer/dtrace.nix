{
  stdenv,
  writeText,
  dtracePackage,
}:

let
  provider = writeText "nixos-port.d" ''
    provider nixos_port {
      probe fire();
    };
  '';
  source = writeText "nixos-port.c" ''
    #include <sys/sdt.h>
    #include <unistd.h>

    static void fire(void)
    {
      DTRACE_PROBE(nixos_port, fire);
    }

    int main(int argc, char **argv)
    {
      if (argc > 1) {
        (void)argv;
        for (;;) {
          sleep(1);
          fire();
        }
      }

      fire();
      return 0;
    }
  '';
in

stdenv.mkDerivation {
  pname = "oracle-dtrace-usdt-fixture";
  inherit (dtracePackage) version;
  dontUnpack = true;
  strictDeps = true;

  nativeBuildInputs = [ dtracePackage ];

  buildPhase = ''
    runHook preBuild
    cp ${provider} nixos-port.d
    cp ${source} nixos-port.c
    PATH=/no-such-path ${dtracePackage}/bin/dtrace \
      -xnolibs -C -h -s nixos-port.d -o nixos-port.h
    $CC -std=gnu99 -I${dtracePackage}/lib/dtrace/include \
      -c nixos-port.c -o nixos-port.o
    dtrace -xnolibs -G -s nixos-port.d nixos-port.o -o nixos-port-prov.o
    $CC nixos-port.o nixos-port-prov.o -o nixos-port
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 nixos-port "$out/bin/nixos-port"
    install -Dm644 nixos-port.d "$out/share/dtrace/nixos-port.d"
    install -Dm644 nixos-port.h "$out/include/nixos-port.h"
    runHook postInstall
  '';
}
