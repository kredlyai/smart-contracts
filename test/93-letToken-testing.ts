import hre, { deployments, ethers, getNamedAccounts, network } from "hardhat";
import { ANY_CONTRACT, getTokenConfig, globalConfig } from "../helpers/deploymentConfig";
import { getUnregisteredPools, toAddress } from "../helpers/deploymentUtils";
import { formatUnits, parseUnits } from "ethers/lib/utils";

describe("lending and borrowing test", () => {
    before(async function () {
        this.deploy = deployments.deploy;
        this.deployer = (await getNamedAccounts()).deployer;
    });

    it("set pool and market", async function () {
        const { poolConfig } = globalConfig[network.name];
        const unregisteredPools = await getUnregisteredPools(poolConfig, hre);
        let pool = unregisteredPools[0];

        this.leToken1 = pool.letokens[0]
        this.leToken2 = pool.letokens[1]
    })

    it("lend token1 from market", async function () {
        const { tokensConfig } = globalConfig[network.name];
        const { asset, symbol } = this.leToken1
        const leTokenContractAddress = (await ethers.getContract(`LeToken_${symbol}`)).address;
        const leTokenContract = await ethers.getContractAt("LeToken", leTokenContractAddress)
        const token = getTokenConfig(asset, tokensConfig);
        let tokenContract;
        if (token.isMock) {
            tokenContract = await ethers.getContract(`Mock${token.symbol}`);
        } else {
            tokenContract = await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/ERC20.sol:ERC20", token.tokenAddress)
        }

        // approve underlying token
        let lendAmount = BigInt(1) * BigInt(1e18); // 100
        var tx = await tokenContract.approve(leTokenContract.address, lendAmount);
        await tx.wait();

        // mint
        tx = await leTokenContract.mint(lendAmount, []);
        await tx.wait();
    })

    it("borrow token2 from market", async function () {
        const { symbol } = this.leToken2
        const leTokenContractAddress = (await ethers.getContract(`LeToken_${symbol}`)).address;
        const leTokenContract = await ethers.getContractAt("LeToken", leTokenContractAddress)

        var tx = await leTokenContract.borrow(parseUnits("1"), []);
        await tx.wait();
    })

    it("redeem from market", async function () {
        const { tokensConfig } = globalConfig[network.name];
        const { asset, symbol } = this.leToken1
        const leTokenContractAddress = (await ethers.getContract(`LeToken_${symbol}`)).address;
        const leTokenContract = await ethers.getContractAt("LeToken", leTokenContractAddress)
        const token = getTokenConfig(asset, tokensConfig);
        let tokenContract;
        if (token.isMock) {
            tokenContract = await ethers.getContract(`Mock${token.symbol}`);
        } else {
            tokenContract = await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/ERC20.sol:ERC20", token.tokenAddress)
        }

        // redeem
        let beforeTokenBalance = await tokenContract.balanceOf(this.deployer)
        let lendAmount = await leTokenContract.balanceOf(this.deployer)
        var tx = await leTokenContract.redeem(lendAmount.div(5), []);
        await tx.wait();

        let aftertokenBalance = await tokenContract.balanceOf(this.deployer)
        console.log(`beforeTokenBalance ${formatUnits(beforeTokenBalance)}, afterTokenBalance ${formatUnits(aftertokenBalance)}`);
    })


    it("lend token1 from market", async function () {
        const { tokensConfig } = globalConfig[network.name];
        const { asset, symbol } = this.leToken1
        const leTokenContractAddress = (await ethers.getContract(`LeToken_${symbol}`)).address;
        const leTokenContract = await ethers.getContractAt("LeToken", leTokenContractAddress)
        const token = getTokenConfig(asset, tokensConfig);
        let tokenContract;
        if (token.isMock) {
            tokenContract = await ethers.getContract(`Mock${token.symbol}`);
        } else {
            tokenContract = await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/ERC20.sol:ERC20", token.tokenAddress)
        }

        // approve underlying token
        let lendAmount = BigInt(1) * BigInt(1e18); // 100
        var tx = await tokenContract.approve(leTokenContract.address, lendAmount);
        await tx.wait();

        // mint
        tx = await leTokenContract.mint(lendAmount, []);
        await tx.wait();
    })

    it("borrow token2 from market", async function () {
        const { symbol } = this.leToken2
        const leTokenContractAddress = (await ethers.getContract(`LeToken_${symbol}`)).address;
        const leTokenContract = await ethers.getContractAt("LeToken", leTokenContractAddress)
        
        var tx = await leTokenContract.borrow(parseUnits("1"), []);
        await tx.wait();
    })

    it("redeem from market", async function () {
        const { tokensConfig } = globalConfig[network.name];
        const { asset, symbol } = this.leToken1
        const leTokenContractAddress = (await ethers.getContract(`LeToken_${symbol}`)).address;
        const leTokenContract = await ethers.getContractAt("LeToken", leTokenContractAddress)
        const token = getTokenConfig(asset, tokensConfig);
        let tokenContract;
        if (token.isMock) {
            tokenContract = await ethers.getContract(`Mock${token.symbol}`);
        } else {
            tokenContract = await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/ERC20.sol:ERC20", token.tokenAddress)
        }

        // redeem
        let beforeTokenBalance = await tokenContract.balanceOf(this.deployer)
        let lendAmount = await leTokenContract.balanceOf(this.deployer)
        var tx = await leTokenContract.redeem(lendAmount.div(5), []);
        await tx.wait();

        let aftertokenBalance = await tokenContract.balanceOf(this.deployer)
        console.log(`beforeTokenBalance ${formatUnits(beforeTokenBalance)}, afterTokenBalance ${formatUnits(aftertokenBalance)}`);
    })
})