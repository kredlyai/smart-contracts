import hre, { deployments, ethers, getNamedAccounts, network } from "hardhat";
import { DeployResult } from "hardhat-deploy/types";
import { BLOCKS_PER_YEAR, InterestRateModels, getTokenAddress, getTokenConfig, globalConfig } from "../helpers/deploymentConfig";
import { getUnregisteredPools, getUnregisteredRewardsDistributors, toAddress } from "../helpers/deploymentUtils";
import { parseUnits } from "ethers/lib/utils";
import { BigNumber, BigNumberish } from "ethers";
import { AddressOne } from "../helpers/utils";

const mantissaToBps = (num: BigNumberish) => {
    return BigNumber.from(num).div(parseUnits("1", 14)).toString();
};

describe("Deploy leTokens", () => {
    before(async function () {
        this.deploy = deployments.deploy;
        this.deployer = (await getNamedAccounts()).deployer;
    });

    it("RewardsDistributor implement deployment", async function () {
        await this.deploy("RewardsDistributorImpl", {
            contract: "RewardsDistributor",
            from: this.deployer,
            autoMine: true,
            log: true,
            skipIfAlreadyDeployed: true,
        })
    })

    it("Deploying RewardsDistributor", async function () {
        const { tokensConfig, poolConfig, preconfiguredAddresses } = globalConfig[network.name];
        const accessControlManagerAddress = await toAddress(
            preconfiguredAddresses.AccessControlManager || "AccessControlManager",
            hre,
        );
        const maxLoopsLimit = 100;

        const pools = await getUnregisteredRewardsDistributors(poolConfig, hre);
        for (const pool of pools) {
            const rewards = pool.rewards;
            if (!rewards) continue;

            const comptrollerProxy = await ethers.getContract(`Comptroller_${pool.id}`);
            for (const [idx, reward] of rewards.entries()) {
                // Get reward token address
                const tokenConfig = getTokenConfig(reward.asset, tokensConfig);
                const rewardTokenAddress = await getTokenAddress(tokenConfig, deployments);
                const contractName = `RewardsDistributor_${pool.id}_${idx}`;

                await this.deploy(contractName, {
                    from: this.deployer,
                    contract: "RewardsDistributor",
                    proxy: {
                        implementationName: `RewardsDistributorImpl`,
                        owner: this.deployer,
                        proxyContract: "OpenZeppelinTransparentProxy",
                        execute: {
                            methodName: "initialize",
                            args: [comptrollerProxy.address, rewardTokenAddress, maxLoopsLimit, accessControlManagerAddress],
                        },
                        upgradeIndex: 0,
                    },
                    autoMine: true,
                    log: true,
                    skipIfAlreadyDeployed: true,
                })
            }
        }
    })
})