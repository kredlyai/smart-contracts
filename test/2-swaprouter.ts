import { deployments, ethers, getNamedAccounts, network } from "hardhat";

describe("deploy swap router", () => {
    before(async function () {
        this.deploy = deployments.deploy;
        this.deployer = (await getNamedAccounts()).deployer;
    });
    if (network.name !== "mantle") {
        it("swap factory deployment", async function () {
            await this.deploy("swapFactory", {
                from: this.deployer,
                contract: "UniswapV2Factory",
                args: [this.deployer],
                log: true,
                autoMine: true,
            });
        })

        it("swap wETH deployment", async function () {
            await this.deploy("swapWETH", {
                from: this.deployer,
                contract: "WETH",
                args: [],
                log: true,
                autoMine: true,
            });
        })

        it("swap router deployment", async function () {
            const swapFactory = await ethers.getContract("swapFactory");
            console.log("INIT_CODE_PAIR_HASH", await swapFactory.INIT_CODE_PAIR_HASH());

            const wETH = await ethers.getContract("swapWETH");
            await this.deploy("swapRouter", {
                from: this.deployer,
                contract: "UniswapV2Router02",
                args: [swapFactory.address, wETH.address],
                log: true,
                autoMine: true,
            });
        })
    }
})