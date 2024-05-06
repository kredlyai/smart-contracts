import hre, { deployments, ethers, getNamedAccounts, network } from "hardhat";
import { globalConfig } from "../helpers/deploymentConfig";
import { getUnregisteredPools, toAddress } from "../helpers/deploymentUtils";

describe("Deploy Protocol share Reserve", () => {
    before(async function () {
        this.deploy = deployments.deploy;
        this.deployer = (await getNamedAccounts()).deployer;
    });

    it("ProtocolShareReserve deployment", async function () {
        const { preconfiguredAddresses } = globalConfig[hre.network.name];
        const accessControlManagerAddress = await toAddress(
            preconfiguredAddresses.AccessControlManager || "AccessControlManager",
            hre,
        );
        await this.deploy("ProtocolShareReserve", {
            from: this.deployer,
            contract: "ProtocolShareReserve",
            proxy: {
                owner: this.deployer,
                proxyContract: "OpenZeppelinTransparentProxy",
                execute: {
                    methodName: "initialize",
                    args: [accessControlManagerAddress, 100],
                },
                upgradeIndex: 0,
            },
            autoMine: true,
            log: true,
        })
    })

    it("set PoolRegistry to ProtocolShareReserve", async function () {
        const protocolShareReserve = await ethers.getContract(`ProtocolShareReserve`);
        const poolRegistry = await ethers.getContract(`PoolRegistry`);
        var tx = await protocolShareReserve.setPoolRegistry(poolRegistry.address)
        await tx.wait();
    })

    it("set ProtocolShareReserve to leTokens", async function () {
        const { poolConfig } = globalConfig[network.name];
        const protocolShareReserve = await ethers.getContract(`ProtocolShareReserve`);

        const unregisteredPools = await getUnregisteredPools(poolConfig, hre);
        for (const pool of unregisteredPools) {
            for (const letoken of pool.letokens) {
                const leTokenContractAddress = (await ethers.getContract(`LeToken_${letoken.symbol}`)).address;
                const leTokenContract = await ethers.getContractAt("LeToken", leTokenContractAddress)
                var tx = await leTokenContract.setProtocolShareReserve(
                    protocolShareReserve.address
                );
                await tx.wait()
            }
        }
    })
})