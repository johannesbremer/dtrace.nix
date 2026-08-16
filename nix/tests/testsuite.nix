{
  pkgs,
  dtracePackage,
}:

let
  binPath = package: name: "${package}/bin/${name}";
  replaceCommands =
    prefix: package: names:
    map (name: [
      "${prefix}/${name}"
      (binPath package name)
    ]) names;
  replacements = [
    [
      "/usr/sbin/dtrace"
      (binPath dtracePackage "dtrace")
    ]
  ]
  ++ replaceCommands "/usr/bin" pkgs.binutils [
    "nm"
    "objcopy"
    "objdump"
    "readelf"
  ]
  ++ replaceCommands "/usr/bin" pkgs.coreutils [
    "basename"
    "nohup"
    "sleep"
  ]
  ++ replaceCommands "/usr/bin" pkgs.gawk [
    "awk"
    "gawk"
  ]
  ++ replaceCommands "/usr/bin" pkgs.jdk [
    "java"
    "javac"
  ]
  ++ [
    [
      "/usr/bin/bash"
      (binPath pkgs.bash "bash")
    ]
    [
      "/usr/bin/cpp"
      (binPath pkgs.stdenv.cc "cpp")
    ]
    [
      "/usr/bin/gcc"
      (binPath pkgs.stdenv.cc "gcc")
    ]
    [
      "/usr/bin/perf"
      (binPath pkgs.perf "perf")
    ]
    [
      "/usr/bin/perl"
      (binPath pkgs.perl "perl")
    ]
    [
      "/usr/bin/sed"
      (binPath pkgs.gnused "sed")
    ]
    [
      "/usr/bin/time"
      (binPath pkgs.time "time")
    ]
    [
      "/usr/bin/tshark"
      (binPath pkgs.wireshark-cli "tshark")
    ]
    [
      "/sbin/ip"
      (binPath pkgs.iproute2 "ip")
    ]
  ]
  ++ replaceCommands "/bin" pkgs.coreutils [
    "cat"
    "date"
    "echo"
    "kill"
    "ls"
    "sleep"
    "true"
  ]
  ++ [
    [
      "/bin/bash"
      (binPath pkgs.bash "bash")
    ]
  ];
  replacementScript = pkgs.lib.concatMapStringsSep "\n" (
    replacement:
    let
      from = builtins.elemAt replacement 0;
      to = builtins.elemAt replacement 1;
    in
    ''
      while IFS= read -r file; do
        FHS_FROM='${from}' STORE_TO='${to}' ${pkgs.perl}/bin/perl -pi -e \
          's{(?<![A-Za-z0-9._+~-])\Q$ENV{FHS_FROM}\E}{$ENV{STORE_TO}}g' \
          "$file"
      done < <(grep -rIl -F -- '${from}' "$out" || true)
    ''
  ) replacements;
in

pkgs.runCommand "oracle-dtrace-testsuite-${dtracePackage.version}"
  {
    nativeBuildInputs = [ pkgs.patch ];
    strictDeps = true;
  }
  ''
    cp -R ${dtracePackage.testsuite}/share/dtrace/testsuite "$out"
    chmod -R u+w "$out"

    patch -d "$out" -p1 < ${../patches/fix-pidprobes-pie-test.patch}
    patch -d "$out" -p1 < ${../patches/fix-runtest-core-pattern-restore.patch}
    patch -d "$out" -p1 < ${../patches/fix-testsuite-portability.patch}

    ${replacementScript}
    patchShebangs "$out"

    for postprocessor in "$out"/test/internals/libproc/tst.pldd*.r.p; do
      substituteInPlace "$postprocessor" \
        --replace-fail \
          's:/usr/lib:/lib:g' \
          's:/usr/lib:/lib:g
    s:/nix/store/[^ /,)]*-glibc-[^ /,)]*/lib/libc\.so\.6:/lib64/libc.so.6:g
    s:/nix/store/[^ /,)]*-glibc-[^ /,)]*/lib/ld-linux-x86-64\.so\.2:/lib64/ld-linux-x86-64.so.2:g
    s:/nix/store/[^ /,)]*-glibc-[^ /,)]*/lib/ld-linux-aarch64\.so\.1:/lib/ld-linux-aarch64.so.1:g'
    done
  ''
