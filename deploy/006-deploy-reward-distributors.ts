import { ethers } from "hardhat";
import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { globalConfig, getTokenAddress, getTokenConfig } from "../helpers/deploymentConfig";
import { getUnregisteredRewardsDistributors, toAddress } from "../helpers/deploymentUtils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts } = hre;
  const { deployer } = await getNamedAccounts();
  const { deploy } = deployments;

  const maxLoopsLimit = 100;
  const { tokensConfig, poolConfig, preconfiguredAddresses } = globalConfig[network.name];
  const AccessControlManager = preconfiguredAddresses.AccessControlManager || "AccessControlManager";
  const accessControlAddress = await toAddress(AccessControlManager, hre);
  const pools = await getUnregisteredRewardsDistributors(poolConfig, hre);

  await deploy("RewardsDistributorImpl", {
    contract: "RewardsDistributor",
    from: deployer,
    autoMine: true,
    log: true,
    skipIfAlreadyDeployed: true,
  })

  for (const pool of pools) {
    const rewards = pool.rewards;
    if (!rewards) continue;

    const comptrollerProxy = await ethers.getContract(`Comptroller_${pool.id}`);
    for (const [idx, reward] of rewards.entries()) {
      // Get reward token address
      const tokenConfig = getTokenConfig(reward.asset, tokensConfig);
      const rewardTokenAddress = await getTokenAddress(tokenConfig, deployments);
      // Custom contract name so we can obtain the proxy after that easily
      const contractName = `RewardsDistributor_${pool.id}_${idx}`;

      await deploy(contractName, {
        from: deployer,
        contract: "RewardsDistributor",
        proxy: {
          implementationName: `RewardsDistributorImpl`,
          owner: deployer,
          proxyContract: "OpenZeppelinTransparentProxy",
          execute: {
            methodName: "initialize",
            args: [comptrollerProxy.address, rewardTokenAddress, maxLoopsLimit, accessControlAddress],
          },
          upgradeIndex: 0,
        },
        autoMine: true,
        log: true,
        skipIfAlreadyDeployed: true,
      })
    }
  }
}

func.tags = ["Rewards", "il"];
export default func;
