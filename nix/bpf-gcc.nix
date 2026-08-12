{
  stdenv,
  lib,
  gcc14,
  bpf-binutils,
  bison,
  flex,
  gmp,
  libmpc,
  mpfr,
  perl,
  texinfo,
  which,
  zlib,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "dtrace-bpf-gcc";
  inherit (gcc14.cc) version src;

  patches = gcc14.cc.patches or [ ];

  nativeBuildInputs = [
    bison
    flex
    perl
    texinfo
    which
  ];

  buildInputs = [
    gmp
    libmpc
    mpfr
    zlib
  ];

  configureFlags = [
    "--target=bpf-unknown-none"
    "--enable-languages=c"
    "--disable-bootstrap"
    "--disable-decimal-float"
    "--disable-fixed-point"
    "--disable-hosted-libstdcxx"
    "--disable-libatomic"
    "--disable-libgcc"
    "--disable-libgomp"
    "--disable-libquadmath"
    "--disable-libsanitizer"
    "--disable-libssp"
    "--disable-libstdcxx"
    "--disable-multilib"
    "--disable-nls"
    "--disable-shared"
    "--disable-threads"
    "--with-as=${bpf-binutils}/bin/bpf-unknown-none-as"
    "--with-ld=${bpf-binutils}/bin/bpf-unknown-none-ld"
    "--with-system-zlib"
    "--without-headers"
  ];

  # GCC 14's own libcpp is not clean under the host GCC 15
  # -Werror=format-security flag injected by the Nix hardening wrapper.
  hardeningDisable = [ "format" ];

  preConfigure = ''
    export PATH=${bpf-binutils}/bin:$PATH
    mkdir ../build
    cd ../build
    configureScript=../$sourceRoot/configure
  '';

  buildFlags = [ "all-gcc" ];
  installTargets = [ "install-gcc" ];
  enableParallelBuilding = true;

  postInstall = ''
    rm -rf "$out/share/info" "$out/share/man"
  '';

  passthru = { inherit bpf-binutils; };

  meta = {
    description = "GCC C compiler targeting eBPF for DTrace";
    homepage = "https://gcc.gnu.org/";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.linux;
  };
})
