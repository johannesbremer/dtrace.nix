{
  stdenv,
  lib,
  src,
  bpf-binutils,
  bpf-gcc,
  bash,
  bison,
  coreutils,
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
  wireshark-cli,
  zlib,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "oracle-dtrace";
  version = "2.0.7";
  inherit src;
  strictDeps = true;

  outputs = [
    "out"
    "testsuite"
  ];
  setOutputFlags = false;

  patches = [
    ./patches/fix-fortify-usdt-parser.patch
    ./patches/fix-linux-6.19-syscall-args.patch
    ./patches/fix-usdt-hyphen-function.patch
    ./patches/fix-pid-pie-offset-probes.patch
    ./patches/fix-dtprobed-map-files.patch
    ./patches/authorize-effective-root.patch
    ./patches/fix-btf-function-parameters.patch
    ./patches/fix-modern-bio-page-flags.patch
    ./patches/support-glibc-r-debug-v2.patch
    ./patches/configure-tshark-path.patch
    ./patches/parse-modern-kallsyms.patch
    ./patches/filter-untraceable-fprobes.patch
    ./patches/index-fprobe-eligibility.patch
    ./patches/lazy-kernel-symbols.patch
    ./patches/complete-tracefs-fbt-transition.patch
    ./patches/bound-probe-compilation-memory.patch
    ./patches/suppress-analysis-disassembly.patch
    ./patches/stabilize-emulated-tests.patch
    ./patches/stabilize-ci-regressions.patch
  ];

  nativeBuildInputs = [
    bison
    flex
    gawk
    pkg-config
    bpf-binutils
    bpf-gcc
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
    # Upstream ships io.d.in alongside pre-generated translators for each
    # supported architecture and kernel series.  Builds without a kernel
    # source tree install those generated files, so keep them in sync with
    # fix-modern-bio-page-flags.patch.
    for ioD in dlibs/*/*/io.d; do
      kernelSeries=$(basename "$(dirname "$ioD")")
      case "$kernelSeries" in
        5.2|5.6)
          pageIo='((int)B->bi_flags & (1 << 6) ? B_PAGEIO : B_PHYS);'
          ;;
        5.11|5.12|5.14|5.16|6.1)
          pageIo='((int)B->bi_flags & 0 ? B_PAGEIO : B_PHYS);'
          ;;
        6.10)
          pageIo='((int)B->bi_flags & 1 ? B_PAGEIO : B_PHYS);'
          ;;
        *)
          echo "Unsupported pre-generated io.d kernel series: $kernelSeries" >&2
          exit 1
          ;;
      esac

      substituteInPlace "$ioD" \
        --replace-fail $'/* bit # in bi_flags */\ninline int BIO_USER_MAPPED = 6;\n\n' "" \
        --replace-fail \
          '((int)B->bi_flags & (1 << BIO_USER_MAPPED) ? B_PAGEIO : B_PHYS);' \
          "$pageIo"
    done

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
    substituteInPlace libdtrace/dt_open.c \
      --replace-fail \
        'static const char *_dtrace_defcpp = "cpp";' \
        'static const char *_dtrace_defcpp = "${stdenv.cc}/bin/cpp";' \
      --replace-fail \
        'static const char *_dtrace_defld = "ld";' \
        'static const char *_dtrace_defld = "${binutils-unwrapped}/bin/ld";'
    # Keep tshark in the runtime closure while allowing callers to explicitly
    # select the documented tracemem fallback through DTRACE_TSHARK.
    substituteInPlace libdtrace/dt_pcap.c \
      --replace-fail \
        '@tshark@' \
        '${wireshark-cli}/bin/tshark'
    substituteInPlace test/triggers/Build \
      --replace-fail \
        'visible-constructor visible-constructor-static visible-constructor-static-unstripped' \
        'visible-constructor' \
      --replace-fail \
        '-Wl,-rpath test/triggers' \
        "-Wl,-rpath,'\$\$\$\$ORIGIN'"
    substituteInPlace test/triggers/pid-tst-gcc.c \
      --replace-fail /bin/ls ${coreutils}/bin/ls
  '';

  enableParallelBuilding = true;

  installTargets = [
    "install"
    "install-test"
  ];

  postInstall = ''
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
