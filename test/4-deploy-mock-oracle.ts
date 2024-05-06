import { deployments, ethers, getNamedAccounts, network } from "hardhat";
import { globalConfig } from "../helpers/deploymentConfig";

describe("Oracle deployment", () => {
    before(async function () {
        this.deploy = deployments.deploy;
        this.deployer = (await getNamedAccounts()).deployer;
        this.networkName = network.name === "hardhat" ? "mantle" : network.name;
    });
    if (network.name === "hardhat") {
        it("deploy mock oracle", async function () {
            await this.deploy(`mockPriceOracle`, {
                from: this.deployer,
                log: true,
                deterministicDeployment: false,
                args: [],
                autoMine: true,
                contract: "MockPriceOracle",
            });
        })
        it("set prices of token", async function () {
            for (const token of globalConfig[this.networkName].tokensConfig) {

                const priceOracle = await ethers.getContract(`mockPriceOracle`)
                const mockToken = await ethers.getContract(`Mock${token.symbol}`)

                const price = BigInt(1) * BigInt(10 ** 18);
                let tx = await priceOracle.setPrice(mockToken.address, price)
                await tx.wait();
            }
        })
    }
})