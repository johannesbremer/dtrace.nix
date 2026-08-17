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
    perTestTimeout = {
      core = 41;
      long = 120;
      stress = 600;
    };
    shardCounts = {
      core = 4;
      long = 2;
      stress = 4;
    };
  };

  emulated = common // {
    requiredFeatures.kvm = false;
    qemuAcceleration = false;
    perTestTimeout = {
      core = 300;
      long = 600;
      stress = 1200;
    };
    shardCounts = {
      core = 16;
      long = 4;
      stress = 8;
    };
  };
}
