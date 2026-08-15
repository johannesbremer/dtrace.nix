{
  stdenv,
  lib,
  src,
  bpf-binutils,
  bpf-gcc,
  bash,
  bison,
  flex,
  gawk,
  pkg-config,
  binutils-unwrapped,
  elfutils,
  fuse3,
  libbpf,
  libpcap,
  libpfm,
  linuxHeaders,
  systemdLibs,
  zlib,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "oracle-dtrace";
  version = "2.0.7";
  inherit src;

  outputs = [
    "out"
    "testsuite"
  ];
  setOutputFlags = false;

  patches = [
    ./patches/fix-fortify-usdt-parser.patch
    ./patches/fix-linux-6.19-syscall-args.patch
    ./patches/authorize-effective-root.patch
    ./patches/add-declared-timeout-cutoff.patch
    ./patches/relax-raise3-deadlines.patch
    ./patches/fix-runtest-core-pattern-restore.patch
  ];

  nativeBuildInputs = [
    bison
    flex
    gawk
    pkg-config
  ];

  buildInputs = [
    binutils-unwrapped.dev
    binutils-unwrapped.lib
    elfutils
    fuse3
    libbpf
    libpcap
    libpfm
    linuxHeaders
    systemdLibs
    zlib
  ];

  configureFlags = [
    "--prefix=${placeholder "out"}"
    "--bindir=${placeholder "out"}/bin"
    "--sbindir=${placeholder "out"}/bin"
    "--libdir=${placeholder "out"}/lib"
    "--includedir=${placeholder "out"}/include"
    "--mandir=${placeholder "out"}/share/man"
    "--docdir=${placeholder "out"}/share/doc/dtrace"
    "--testdir=${placeholder "testsuite"}/share/dtrace/testsuite"
    "--pkg-config-dir=${placeholder "out"}/lib/pkgconfig"
    "--udevdir=${placeholder "out"}/lib/udev/rules.d"
    "--without-systemd"
    "--user-uid=1000"
    "HAVE_FUSE_LOG=yes"
    "HAVE_LIBFUSE3=yes"
    "HAVE_LIBCTF=yes"
    "BPFC=${bpf-gcc}/bin/bpf-unknown-none-gcc"
    "BPFLD=${bpf-binutils}/bin/bpf-unknown-none-ld"
  ];

  BPFCPPFLAGS = "-I${linuxHeaders}/include -I${libbpf}/include";

  makeFlags = [ "SHELL=${bash}/bin/bash" ];

  postPatch = ''
    patchShebangs configure include libdtrace libproc test runtest.sh
    substituteInPlace GNUmakefile \
      --replace-fail 'SHELL = /bin/bash' 'SHELL = ${bash}/bin/bash'
    substituteInPlace include/Build \
      --replace-fail /usr/include/bpf/bpf_helper_defs.h \
        ${libbpf}/include/bpf/bpf_helper_defs.h
    substituteInPlace libproc/mkoffsets.sh \
      --replace-fail '-x c - >/dev/null' '-x c - -lc >/dev/null'
    substituteInPlace cmd/Build \
      --replace-fail '#!/bin/bash' '#!${bash}/bin/bash'
    substituteInPlace runtest.sh \
      --replace-fail /usr/bin/cpp ${stdenv.cc}/bin/cpp
    substituteInPlace libdtrace/dt_open.c \
      --replace-fail \
        'static const char *_dtrace_defcpp = "cpp";' \
        'static const char *_dtrace_defcpp = "${stdenv.cc}/bin/cpp";' \
      --replace-fail \
        'static const char *_dtrace_defld = "ld";' \
        'static const char *_dtrace_defld = "${binutils-unwrapped}/bin/ld";'
    substituteInPlace test/triggers/Build \
      --replace-fail \
        'visible-constructor visible-constructor-static visible-constructor-static-unstripped' \
        'visible-constructor'
  '';

  enableParallelBuilding = true;

  installTargets = [
    "install"
    "install-test"
  ];

  postInstall = ''
    rm -f "$out/lib/udev/rules.d/60-dtprobed.rules"
    rm -f "$out/lib/systemd/system/dtprobed.service"
    rm -f "$out/lib/systemd/system/dtrace-usdt.target"
    rm -rf "$out/lib/systemd/system-preset"
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    "$out/bin/dtrace" -Vv 2>&1 \
      | grep -Fx 'This is DTrace ${finalAttrs.version}'
    test -x "$out/bin/dtprobed"
    test -f "$out/lib/dtrace/drti/drti.o"
    grep -aFq '${stdenv.cc}/bin/cpp' "$out/lib/libdtrace.so"
    runHook postInstallCheck
  '';

  passthru = {
    inherit bpf-binutils bpf-gcc;
  };

  meta = {
    description = "Dynamic tracing framework for Linux";
    homepage = "https://github.com/oracle/dtrace";
    changelog = "https://github.com/oracle/dtrace/releases";
    license = lib.licenses.upl;
    mainProgram = "dtrace";
    platforms = lib.platforms.linux;
  };
})
