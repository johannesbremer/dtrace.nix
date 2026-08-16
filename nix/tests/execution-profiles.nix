let
  common = {
    longTestCutoff = 41;
    globalTimeout = 105 * 60;
    memorySize = {
      core = 8192;
      long = 8192;
      stress = 8192;
    };
    swapSize = {
      core = 2048;
      long = 2048;
      stress = 8192;
    };
    cores = 4;
  };
in
{
  accelerated = common // {
    requiredFeatures.kvm = true;
    qemuAcceleration = true;
    perTestTimeout = 41;
    shardCounts = {
      core = 4;
      long = 2;
      stress = 4;
    };
  };

  emulated = common // {
    requiredFeatures.kvm = false;
    qemuAcceleration = false;
    perTestTimeout = 120;
    shardCounts = {
      core = 16;
      long = 4;
      stress = 8;
    };
  };
}
