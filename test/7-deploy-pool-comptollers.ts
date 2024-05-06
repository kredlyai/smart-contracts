import hre, { deployments, ethers, getNamedAccounts, network } from "hardhat";
import { DeployResult } from "hardhat-deploy/types";
import { globalConfig } from "../helpers/deploymentConfig";
import { getUnregisteredPools, toAddress } from "../helpers/deploymentUtils";

describe("Deploy comptoller", () => {
    before(async function () {
        this.deploy = deployments.deploy;
        this.deployer = (await getNamedAccounts()).deployer;
    });

    it("comptoller beacon deployment", async function () {
        const poolRegistry = await ethers.getContract("PoolRegistry");
        // Comptroller Beacon
        const comptrollerImpl: DeployResult = await this.deploy("ComptrollerImpl", {
            contract: "Comptroller",
            from: this.deployer,
            args: [poolRegistry.address],
            log: true,
            autoMine: true,
        })

        await this.deploy("ComptrollerBeacon", {
            contract: "UpgradeableBeacon",
            from: this.deployer,
            args: [comptrollerImpl.address],
            log: true,
            autoMine: true,
        })
    })
    it("Deploying a proxy for Comptroller of the pool", async function () {
        const { poolConfig, preconfiguredAddresses } = globalConfig[network.name];
        const comptrollerBeacon = await ethers.getContract("ComptrollerBeacon");
        const accessControlManagerAddress = await toAddress(
            preconfiguredAddresses.AccessControlManager || "AccessControlManager",
            hre,
        );

        const unregisteredPools = await getUnregisteredPools(poolConfig, hre);
        for (const pool of unregisteredPools) {
            // Deploying a proxy for Comptroller
            console.log(`Deploying a proxy for Comptroller of the pool ${pool.name}`);
            const maxLoopsLimit = 100;

            const Comptroller = await ethers.getContractFactory("Comptroller");
            await this.deploy(`Comptroller_${pool.id}`, {
                from: this.deployer,
                contract: "BeaconProxy",
                args: [
                    comptrollerBeacon.address,
                    Comptroller.interface.encodeFunctionData("initialize", [maxLoopsLimit, accessControlManagerAddress]),
                ],
                log: true,
                autoMine: true,
            })
        }
    })
})