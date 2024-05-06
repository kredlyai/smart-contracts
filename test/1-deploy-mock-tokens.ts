import { deployments, ethers, getNamedAccounts, network } from "hardhat";
import { globalConfig } from "../helpers/deploymentConfig";

describe("configure mock tokens", () => {
    before(async function () {
        this.deploy = deployments.deploy;
        this.deployer = (await getNamedAccounts()).deployer;
    });

    if (network.name == "hardhat")
        it("deploy tokens", async function () {
            for (const token of globalConfig[network.name].tokensConfig) {
                console.log(`Configuring ${token.name}`);

                // deploy mock token 
                const initialSupply = BigInt(1e10) * BigInt(10 ** token.decimals);
                await this.deploy(`Mock${token.symbol}`, {
                    from: this.deployer,
                    log: true,
                    deterministicDeployment: false,
                    args: [initialSupply, `Mock${token.name}`, token.decimals, `Mock${token.symbol}`],
                    autoMine: true,
                    contract: "StandardToken",
                });
            }
        })
})