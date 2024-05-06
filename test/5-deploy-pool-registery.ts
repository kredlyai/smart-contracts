import hre, { deployments, ethers, getNamedAccounts, network } from "hardhat";
import { globalConfig } from "../helpers/deploymentConfig";
import { toAddress } from "../helpers/deploymentUtils";

describe("deploy PoolRegistry", () => {
    before(async function () {
        this.deploy = deployments.deploy;
        this.deployer = (await getNamedAccounts()).deployer;
    });

    it("PoolRegistry deployment", async function () {
        const { preconfiguredAddresses } = globalConfig[hre.network.name];
        const accessControlManagerAddress = await toAddress(
            preconfiguredAddresses.AccessControlManager || "AccessControlManager",
            hre,
        );
        await this.deploy("PoolRegistry", {
            from: this.deployer,
            contract: "PoolRegistry",
            proxy: {
                owner: this.deployer,
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
    })
})