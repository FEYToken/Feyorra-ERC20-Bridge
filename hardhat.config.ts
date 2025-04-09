import { type HardhatUserConfig, vars } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";

import "./tasks";

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.24",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  networks: {
    bscTestnet: {
      url: vars.get("BSC_RPC_TESTNET_URL"),
      chainId: 97,
      accounts: [vars.get("DEPLOYER_PRIVATE_KEY")],
    },
    ethSepolia: {
      url: vars.get("ETH_RPC_SEPOLIA_URL"),
      chainId: 11155111,
      accounts: [vars.get("DEPLOYER_PRIVATE_KEY")],
    },
    bsc: {
      url: vars.get("BSC_RPC_URL"),
      chainId: 56,
      accounts: [vars.get("DEPLOYER_PRIVATE_KEY")],
    },
    eth: {
      url: vars.get("ETH_RPC_URL"),
      chainId: 1,
      accounts: [vars.get("DEPLOYER_PRIVATE_KEY")],
    },
  },
};

export default config;
