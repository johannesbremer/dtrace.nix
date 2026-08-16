{
  stdenv,
  lib,
  binutils-unwrapped,
  bison,
  flex,
  perl,
  texinfo,
  zlib,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "dtrace-bpf-binutils";
  inherit (binutils-unwrapped) version src;
  strictDeps = true;

  patches = binutils-unwrapped.patches or [ ];

  nativeBuildInputs = [
    bison
    flex
    perl
    texinfo
  ];

  buildInputs = [ zlib ];

  configureFlags = [
    "--target=bpf-unknown-none"
    "--disable-gdb"
    "--disable-gdbserver"
    "--disable-gprofng"
    "--disable-nls"
    "--disable-sim"
    "--disable-werror"
    "--enable-deterministic-archives"
    "--with-system-zlib"
  ];

  enableParallelBuilding = true;

  postInstall = ''
    rm -rf "$out/share/info" "$out/share/man"
  '';

  meta = {
    description = "GNU Binutils targeting eBPF for DTrace";
    homepage = "https://sourceware.org/binutils/";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.linux;
  };
})
