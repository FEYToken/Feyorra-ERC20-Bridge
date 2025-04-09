import { task, types } from "hardhat/config";

task(
  "predict-address",
  "Predicts the address of a smart contract to be deployed from a specific EOA and nonce position"
)
  .addParam("deployer", "The EOA address from which the deployment will occur")
  .addParam(
    "position",
    "The nonce position for the contract deployment (1 for the next deployment, 2 for the second next, etc.)",
    1,
    types.int
  )
  .setAction(async (taskArgs, hre) => {
    const ethers = hre.ethers;

    const { deployer, position } = taskArgs;
    if (position < 1) {
      throw new Error("Position must be a positive integer");
    }

    if (!ethers.isAddress(deployer)) {
      throw new Error("Invalid deployer address");
    }

    const currentNonce = await ethers.provider.getTransactionCount(deployer);
    const deploymentNonce = currentNonce + position - 1;

    const predictedAddress = ethers.getCreateAddress({
      from: deployer,
      nonce: deploymentNonce,
    });

    console.log(`Predicted smart contract address: ${predictedAddress}`);
  });
