{
  upstreamTest,
}:
{
  # The upstream suite exercises providers backed by optional kernel modules.
  # Load them before DTrace enumerates probes so coverage does not depend on
  # which unrelated service happened to activate a module first.
  boot.kernelModules = [
    "nfs"
    "tun"
    "xfs"
  ];
  services.nfs.server.enable = true;
  services.openssh.enable = true;
  environment.systemPackages = [ upstreamTest ];
}
