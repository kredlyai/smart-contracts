import { deployments, ethers, getNamedAccounts, network } from "hardhat";

describe("deploy PoolLens", () => {
    before(async function () {
        this.deploy = deployments.deploy;
        this.deployer = (await getNamedAccounts()).deployer;
    });

    it("PoolLens deployment", async function () {
        await this.deploy("PoolLens", {
            from: this.deployer,
            args: [],
            log: true,
            autoMine: true,
        })
    })
})