import { ethers } from "hardhat";
import { parseUnits } from "ethers/lib/utils";
import { BigNumber, BigNumberish } from "ethers";
import { DeployFunction } from "hardhat-deploy/types";
import { DeployResult } from "hardhat-deploy/dist/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";

import { AddressOne } from "../helpers/utils";
import { InterestRateModels } from "../helpers/deploymentConfig";
import { getUnregisteredLeTokens, toAddress } from "../helpers/deploymentUtils";
import { BLOCKS_PER_YEAR, globalConfig, getTokenConfig } from "../helpers/deploymentConfig";

const mantissaToBps = (num: BigNumberish) => {
  return BigNumber.from(num).div(parseUnits("1", 14)).toString();
};

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts } = hre;
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const { tokensConfig, poolConfig, preconfiguredAddresses } = globalConfig[hre.network.name];
  const AccessControlManager = preconfiguredAddresses.AccessControlManager || "AccessControlManager";

  const accessControlManagerAddress = await toAddress(AccessControlManager, hre);

  // LeToken Beacon
  const leTokenImpl: DeployResult = await deploy("LeTokenImpl", {
    contract: "LeToken",
    from: deployer,
    args: [],
    log: true,
    autoMine: true,
  })

  const leTokenBeacon: DeployResult = await deploy("LeTokenBeacon", {
    contract: "UpgradeableBeacon",
    from: deployer,
    args: [leTokenImpl.address],
    log: true,
    autoMine: true,
  })

  const poolsWithUnregisteredLeTokens = await getUnregisteredLeTokens(poolConfig, hre);
  for (const pool of poolsWithUnregisteredLeTokens) {
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

        const result: DeployResult = await deploy(rateModelName, {
          from: deployer,
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

        const result: DeployResult = await deploy(rateModelName, {
          from: deployer,
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
      const treasuryAddress = await toAddress(preconfiguredAddresses.LeTreasury, hre);
      const leTokenDecimals = 8;

      const args = [
        tokenContract.address,
        comptrollerProxy.address,
        rateModelAddress,
        parseUnits("1", underlyingDecimals + 18 - leTokenDecimals),
        name,
        symbol,
        leTokenDecimals,
        preconfiguredAddresses.NormalTimelock || deployer, // admin
        accessControlManagerAddress,
        [AddressOne, treasuryAddress],
        reserveFactor,
      ]

      await deploy(`LeToken_${symbol}`, {
        from: deployer,
        contract: "BeaconProxy",
        args: [leTokenBeacon.address, LeToken.interface.encodeFunctionData("initialize", args)],
        log: true,
        autoMine: true,
      })

      console.log(`-----------------------------------------`);
    }
  }
};

func.tags = ["LeTokens", "il"];
export default func;
