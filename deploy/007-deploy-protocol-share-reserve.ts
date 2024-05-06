import { ethers } from "hardhat";
import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { globalConfig } from "../helpers/deploymentConfig";
import { toAddress } from "../helpers/deploymentUtils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts } = hre;
  const { deployer } = await getNamedAccounts();
  const { deploy } = deployments;

  const maxLoopsLimit = 100;
  const { preconfiguredAddresses } = globalConfig[network.name];

  const accessControlManagerAddress = await toAddress(
    preconfiguredAddresses.AccessControlManager || "AccessControlManager",
    hre,
  );
  
  await deploy("ProtocolShareReserve", {
    from: deployer,
    contract: "ProtocolShareReserve",
    proxy: {
      owner: deployer,
      proxyContract: "OpenZeppelinTransparentProxy",
      execute: {
        methodName: "initialize",
        args: [accessControlManagerAddress, maxLoopsLimit],
      },
      upgradeIndex: 0,
    },
    autoMine: true,
    log: true,
  })

  const protocolShareReserve = await ethers.getContract(`ProtocolShareReserve`);
  const poolRegistry = await ethers.getContract(`PoolRegistry`);
  var tx = await protocolShareReserve.setPoolRegistry(poolRegistry.address)
  await tx.wait();
}

func.tags = ["Rewards", "il"];
export default func;
