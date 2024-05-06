import { deployments, ethers, getNamedAccounts, network } from "hardhat";

describe("deploy accessControlManager", () => {
    before(async function () {
        this.deploy = deployments.deploy;
        this.deployer = (await getNamedAccounts()).deployer;
        this.networkName = network.name === "hardhat" ? "mantle" : network.name;
    });

    if (network.name === "hardhat")
        it("AccessControlManager deployment", async function () {
            await this.deploy("AccessControlManager", {
                from: this.deployer,
                contract: "AccessControlManager",
                args: [],
                log: true,
                autoMine: true,
            });
        })
})