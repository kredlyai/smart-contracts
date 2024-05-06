import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { globalConfig } from "../helpers/deploymentConfig";
import { toAddress } from "../helpers/deploymentUtils";
import { ethers, network } from "hardhat";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;

    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();
    const { preconfiguredAddresses } = globalConfig[network.name];
    const AccessControlManager = preconfiguredAddresses.AccessControlManager || "AccessControlManager";

    const accessControlManagerAddress = await toAddress(AccessControlManager, hre);

    await deploy("PoolRegistry", {
        from: deployer,
        contract: "PoolRegistry",
        proxy: {
            owner: deployer,
            proxyContract: "OpenZeppelinTransparentProxy",
            execute: {
                methodName: "initialize",
                args: [accessControlManagerAddress],
            },
            upgradeIndex: 0,
        },
        autoMine: true,
        log: true,
    })
}

func.tags = ["PoolRegistry", "il"];
export default func;