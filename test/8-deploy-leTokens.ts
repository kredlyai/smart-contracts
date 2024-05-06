import hre, { deployments, ethers, getNamedAccounts, network } from "hardhat";
import { DeployResult } from "hardhat-deploy/types";
import { BLOCKS_PER_YEAR, InterestRateModels, getTokenConfig, globalConfig } from "../helpers/deploymentConfig";
import { getUnregisteredPools, toAddress } from "../helpers/deploymentUtils";
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

    it("leToken beacon deployment", async function () {
        const leTokenImpl: DeployResult = await this.deploy("LeTokenImpl", {
            contract: "LeToken",
            from: this.deployer,
            args: [],
            log: true,
            autoMine: true,
        })

        await this.deploy("LeTokenBeacon", {
            contract: "UpgradeableBeacon",
            from: this.deployer,
            args: [leTokenImpl.address],
            log: true,
            autoMine: true,
        })
    })

    it("Deploying markets", async function () {
        const { tokensConfig, poolConfig, preconfiguredAddresses } = globalConfig[network.name];
        const accessControlManagerAddress = await toAddress(
            preconfiguredAddresses.AccessControlManager || "AccessControlManager",
            hre,
        );

        const leTokenBeacon = await ethers.getContract("LeTokenBeacon");

        const unregisteredPools = await getUnregisteredPools(poolConfig, hre);
        for (const pool of unregisteredPools) {
            const comptrollerProxy = await ethers.getContract(`Comptroller_${pool.id}`);
            // Deploy Markets
            for (const letoken of pool.letokens) {
                const { name, asset, symbol, rateModel, baseRatePerYear, multiplierPerYear, jumpMultiplierPerYear, kink_, reserveFactor } = letoken;

                const token = getTokenConfig(asset, tokensConfig);
                let tokenContract;

                if (token.isMock) {
                    tokenContract = await ethers.getContract(`Mock${token.symbol}`);
                } else {
                    tokenContract = await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/ERC20.sol:ERC20", token.tokenAddress)
                }

                let rateModelAddress: string;
                if (rateModel === InterestRateModels.JumpRate.toString()) {
                    const [b, m, j, k] = [baseRatePerYear, multiplierPerYear, jumpMultiplierPerYear, kink_].map(mantissaToBps);
                    const rateModelName = `KinkedRateModelV2_base${b}bps_slope${m}bps_jump${j}bps_kink${k}bps`;
                    console.log(`Deploying interest rate model ${rateModelName}`);

                    const result: DeployResult = await this.deploy(rateModelName, {
                        from: this.deployer,
                        contract: "KinkedRateModelV2",
                        args: [
                            BLOCKS_PER_YEAR,
                            baseRatePerYear,
                            multiplierPerYear,
                            jumpMultiplierPerYear,
                            kink_,
                            accessControlManagerAddress,
                        ],
                        log: true,
                        autoMine: true,
                    })

                    rateModelAddress = result.address;
                } else {
                    const [b, m] = [baseRatePerYear, multiplierPerYear].map(mantissaToBps);
                    const rateModelName = `WhitePaperInterestRateModel_base${b}bps_slope${m}bps`;
                    console.log(`Deploying interest rate model ${rateModelName}`);

                    const result: DeployResult = await this.deploy(rateModelName, {
                        from: this.deployer,
                        contract: "LinearInterestRateModel",
                        args: [BLOCKS_PER_YEAR, baseRatePerYear, multiplierPerYear],
                        log: true,
                        autoMine: true,
                    })

                    rateModelAddress = result.address;
                }

                console.log(`Deploying LeToken proxy for ${symbol}`);
                const LeToken = await ethers.getContractFactory("LeToken");
                const underlyingDecimals = Number(await tokenContract.decimals());
                const treasuryAddress = await toAddress(preconfiguredAddresses.LeTreasury || "LeTreasury", hre);
                const leTokenDecimals = 8;

                const args = [
                    tokenContract.address,
                    comptrollerProxy.address,
                    rateModelAddress,
                    parseUnits("1", underlyingDecimals + 18 - leTokenDecimals),
                    name,
                    symbol,
                    leTokenDecimals,
                    this.deployer, // admin
                    accessControlManagerAddress,
                    [AddressOne, treasuryAddress],
                    reserveFactor,
                ]

                await this.deploy(`LeToken_${symbol}`, {
                    from: this.deployer,
                    contract: "BeaconProxy",
                    args: [leTokenBeacon.address, LeToken.interface.encodeFunctionData("initialize", args)],
                    log: true,
                    autoMine: true,
                })

                console.log(`-----------------------------------------`);
            }
        }
    })
})