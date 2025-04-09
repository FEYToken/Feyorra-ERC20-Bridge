import hre from "hardhat";
import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { ZeroAddress } from "ethers";

const routerAddressByChain: Record<string, string> = {
  ethSepolia: "0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59",
  bscTestnet: "0xE1053aE1857476f36A3C62580FF9b016E8EE8F6f",
  eth: "0x80226fc0Ee2b096224EeAc085Bb9a8cba1146f7D",
  bsc: "0x34B03Cb9086d7D758AC55af71584F81A598759FE",
};

const FeyorraBridgeModule = buildModule("FeyorraBridgeModule", (m) => {
  const isOriginalChain = m.getParameter("isOriginalChain", false);
  const feyorraTokenAddress = m.getParameter(
    "feyorraTokenAddress",
    ZeroAddress
  );
  const immediateOwner = m.getParameter("immediateOwner", ZeroAddress);
  const timeLockedOwner = m.getParameter("timeLockedOwner", ZeroAddress);

  const bridgeLimitBucketRate = m.getParameter("bridgeLimitBucketRate", 0n);
  const bridgeLimitBucketCapacity = m.getParameter(
    "bridgeLimitBucketCapacity",
    0n
  );

  const inLimitBucket = {
    capacity: bridgeLimitBucketCapacity,
    rate: bridgeLimitBucketRate,
  };
  const outLimitBucket = {
    capacity: bridgeLimitBucketCapacity,
    rate: bridgeLimitBucketRate,
  };

  const ccipRouterAddress = routerAddressByChain[hre.network.name];
  if (!ccipRouterAddress) {
    throw new Error(`Unsupported network: ${hre.network.name}`);
  }

  const feyorraBridge = m.contract("FeyorraBridge", [
    ccipRouterAddress,
    feyorraTokenAddress,
    isOriginalChain,
    [inLimitBucket, outLimitBucket],
    immediateOwner,
    timeLockedOwner,
  ]);

  return { feyorraBridge };
});

export default FeyorraBridgeModule;
