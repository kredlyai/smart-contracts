import { ethers } from "hardhat";
import { convertToUnit } from "./utils";
import { DeploymentsExtension } from "hardhat-deploy/types";


export type NetworkConfig = {
	hardhat?: DeploymentConfig;
	mantle?: DeploymentConfig;
	sepolia?: DeploymentConfig;
	mantle_sepolia?: DeploymentConfig;
};

enum InterestRateModels {
	WhitePaper,
	JumpRate,
}

export const ANY_CONTRACT = ethers.constants.AddressZero;
const BLOCKS_PER_YEAR = 10_512_000; // assuming a block is mined every 3 seconds
// const BSC_BLOCKS_PER_YEAR = 10_512_000; // assuming a block is mined every 3 seconds
// const ETH_BLOCKS_PER_YEAR = 2_628_000; // assuming a block is mined every 12 seconds
// const OPBNB_BLOCKS_PER_YEAR = 31_536_000; // assuming a block is mined every 1 seconds


const poolRegistryPermissions = (): AccessControlEntry[] => {
	const methods = [
		"setCollateralFactor(address,uint256,uint256)",
		"setMarketSupplyCaps(address[],uint256[])",
		"setMarketBorrowCaps(address[],uint256[])",
		"setLiquidationIncentive(uint256)",
		"setCloseFactor(uint256)",
		"setMinLiquidatableCollateral(uint256)",
		"supportMarket(address)",
	]

	return methods.map(method => ({
		caller: "PoolRegistry",
		target: ANY_CONTRACT,
		method,
	}))
}

const deployerPermissions = (): AccessControlEntry[] => {
	const methods = [
		"swapPoolsAssets(address[],uint256[],address[][])",
		"addPool(string,address,uint256,uint256,uint256)",
		"addMarket(AddMarketInput)",
		"setRewardTokenSpeeds(address[],uint256[],uint256[])",
		"setReduceReservesBlockDelta(uint256)",
	]

	return methods.map(method => ({
		caller: "account:deployer",
		target: ANY_CONTRACT,
		method,
	}))
}

export const preconfiguredAddresses: PreconfiguredAddresses = {
	hardhat: {
		LeTreasury: "account:deployer"
	},
	mantle: {
		AccessControlManager: "0x5DE2f6501fB48F4838832233Aea564c8fa940d03",
		SwapRouter: "",
		Shortfall: "0xf37530A8a810Fcb501AA0Ecd0B0699388F0F2209",
		LeTreasury: "account:deployer",
		priceOracle: "0x4d9F3111cD9b69b98777e7d252DC4A167AA20317"
	},
	mantle_sepolia: {
		AccessControlManager: "0x3836D5FE9818597dF1758f64C4960c2a22bfb296",
		SwapRouter: "",
		Shortfall: "0x48f9d844364095B1B0B9429A18ec9B4fA5c6Af41",
		LeTreasury: "account:deployer",
		priceOracle: "0x4b410Dd703C4d1eE8771A6d42aD0BB3d11df0B2f"
	},
	sepolia: {
		AccessControlManager: "0x659024D7099078397F3b533992C7D835a08F75de",
		LeTreasury: "account:deployer",
		priceOracle: "0xd5860e5667cb25AB2D15D7E74104CfCc7BD88f3f"
	}
};

const globalConfig: NetworkConfig = {
	hardhat: {
		tokensConfig: [
			{
				isMock: true,
				name: "MNT",
				symbol: "MNT",
				decimals: 18,
				tokenAddress: "0x00a92853EC3084F3C52A6c6C2D744cb98b4bcAc3"
			}, {
				isMock: true,
				name: "wrappedETH",
				symbol: "WETH",
				decimals: 18,
				tokenAddress: "0x5351197Fc3bc4301F885E2085abe17C14724FdD4"
			},
			{
				isMock: true,
				name: "KRAI",
				symbol: "KRAI",
				decimals: 18,
				tokenAddress: "0x12710030e9EfDb9b085b7446C50a8aaAb3Aa7921"
			},
			{
				isMock: true,
				name: "USDC",
				symbol: "USDC",
				decimals: 6,
				tokenAddress: "0x448ca23a0C9d64fEcD4852B29Df0b3193f026300"
			}
		],
		poolConfig: [
			{
				id: "KredlyCorePool",
				name: "Kredly Core Pool",
				closeFactor: convertToUnit("0.5", 18),
				liquidationIncentive: convertToUnit("1.1", 18),
				minLiquidatableCollateral: convertToUnit("100", 18),
				letokens: [
					{
						name: "MNT (KredlyCorePool)",
						asset: "MNT",
						symbol: "leMNT_KredlyCorePool",
						rateModel: InterestRateModels.JumpRate.toString(),
						baseRatePerYear: convertToUnit("0.02", 18),
						multiplierPerYear: convertToUnit("0.1", 18),
						jumpMultiplierPerYear: convertToUnit("3", 18),
						kink_: convertToUnit("0.8", 18),
						collateralFactor: convertToUnit("0.65", 18),
						liquidationThreshold: convertToUnit("0.7", 18),
						reserveFactor: convertToUnit("0.2", 18),
						initialSupply: convertToUnit(10_000, 18),
						supplyCap: convertToUnit(500_000, 18),
						borrowCap: convertToUnit(200_000, 18),
						leTokenReceiver: preconfiguredAddresses.hardhat.LeTreasury,
						reduceReservesBlockDelta: "100",
					},
					{
						name: "WETH (KredlyCorePool)",
						asset: "WETH",
						symbol: "leWETH_KredlyCorePool",
						rateModel: InterestRateModels.JumpRate.toString(),
						baseRatePerYear: convertToUnit("0.02", 18),
						multiplierPerYear: convertToUnit("0.1", 18),
						jumpMultiplierPerYear: convertToUnit("3", 18),
						kink_: convertToUnit("0.8", 18),
						collateralFactor: convertToUnit("0.65", 18),
						liquidationThreshold: convertToUnit("0.7", 18),
						reserveFactor: convertToUnit("0.2", 18),
						initialSupply: convertToUnit(10_000, 18),
						supplyCap: convertToUnit(500_000, 18),
						borrowCap: convertToUnit(200_000, 18),
						leTokenReceiver: preconfiguredAddresses.hardhat.LeTreasury,
						reduceReservesBlockDelta: "100",
					},
					{
						name: "KRAI (KredlyCorePool)",
						asset: "KRAI",
						symbol: "leKRAI_KredlyCorePool",
						rateModel: InterestRateModels.JumpRate.toString(),
						baseRatePerYear: convertToUnit("0.02", 18),
						multiplierPerYear: convertToUnit("0.1", 18),
						jumpMultiplierPerYear: convertToUnit("3", 18),
						kink_: convertToUnit("0.8", 18),
						collateralFactor: convertToUnit("0.65", 18),
						liquidationThreshold: convertToUnit("0.7", 18),
						reserveFactor: convertToUnit("0.2", 18),
						initialSupply: convertToUnit(10_000, 18),
						supplyCap: convertToUnit(500_000, 18),
						borrowCap: convertToUnit(200_000, 18),
						leTokenReceiver: preconfiguredAddresses.hardhat.LeTreasury,
						reduceReservesBlockDelta: "100",
					},
					{
						name: "USDC (KredlyCorePool)",
						asset: "USDC",
						symbol: "leUSDC_KredlyCorePool",
						rateModel: InterestRateModels.JumpRate.toString(),
						baseRatePerYear: convertToUnit("0.02", 18),
						multiplierPerYear: convertToUnit("0.1", 18),
						jumpMultiplierPerYear: convertToUnit("3", 18),
						kink_: convertToUnit("0.8", 18),
						collateralFactor: convertToUnit("0.65", 18),
						liquidationThreshold: convertToUnit("0.7", 18),
						reserveFactor: convertToUnit("0.2", 18),
						initialSupply: convertToUnit(10_000, 6), // USDC has 6 decimals on testnet
						supplyCap: convertToUnit(500_000, 6), // USDC has 6 decimals on testnet
						borrowCap: convertToUnit(200_000, 6), // USDC has 6 decimals on testnet
						leTokenReceiver: preconfiguredAddresses.hardhat.LeTreasury,
						reduceReservesBlockDelta: "100",
					}
				],
				rewards: [
					// {
					// 	asset: "HAY",
					// 	markets: ["HAY"],
					// 	supplySpeeds: ["1860119047619047"], // 1500 HAY over 28 days (806400 blocks)
					// 	borrowSpeeds: ["1860119047619047"], // 1500 HAY over 28 days (806400 blocks)
					// },
				],
			}
		],
		accessControlConfig: [
			...poolRegistryPermissions()
		],
		preconfiguredAddresses: preconfiguredAddresses.hardhat,
	},
	sepolia: {
		tokensConfig: [
			{
				isMock: false,
				name: "MNT",
				symbol: "MNT",
				decimals: 18,
				tokenAddress: "0x00a92853EC3084F3C52A6c6C2D744cb98b4bcAc3"
			}, {
				isMock: false,
				name: "wrappedETH",
				symbol: "WETH",
				decimals: 18,
				tokenAddress: "0x5351197Fc3bc4301F885E2085abe17C14724FdD4"
			},
			{
				isMock: false,
				name: "KRAI",
				symbol: "KRAI",
				decimals: 18,
				tokenAddress: "0x12710030e9EfDb9b085b7446C50a8aaAb3Aa7921"
			},
			{
				isMock: false,
				name: "USDC",
				symbol: "USDC",
				decimals: 6,
				tokenAddress: "0x448ca23a0C9d64fEcD4852B29Df0b3193f026300"
			}
		],
		poolConfig: [
			{
				id: "KredlyCorePool",
				name: "Kredly Core Pool",
				closeFactor: convertToUnit("0.5", 18),
				liquidationIncentive: convertToUnit("1.1", 18),
				minLiquidatableCollateral: convertToUnit("100", 18),
				letokens: [
					{
						name: "MNT (KredlyCorePool)",
						asset: "MNT",
						symbol: "leMNT_KredlyCorePool",
						rateModel: InterestRateModels.JumpRate.toString(),
						baseRatePerYear: convertToUnit("0.02", 18),
						multiplierPerYear: convertToUnit("0.1", 18),
						jumpMultiplierPerYear: convertToUnit("3", 18),
						kink_: convertToUnit("0.8", 18),
						collateralFactor: convertToUnit("0.65", 18),
						liquidationThreshold: convertToUnit("0.7", 18),
						reserveFactor: convertToUnit("0.2", 18),
						initialSupply: convertToUnit(10_000, 18),
						supplyCap: convertToUnit(500_000, 18),
						borrowCap: convertToUnit(200_000, 18),
						leTokenReceiver: preconfiguredAddresses.sepolia.LeTreasury,
						reduceReservesBlockDelta: "100",
					},
					{
						name: "WETH (KredlyCorePool)",
						asset: "WETH",
						symbol: "leWETH_KredlyCorePool",
						rateModel: InterestRateModels.JumpRate.toString(),
						baseRatePerYear: convertToUnit("0.02", 18),
						multiplierPerYear: convertToUnit("0.1", 18),
						jumpMultiplierPerYear: convertToUnit("3", 18),
						kink_: convertToUnit("0.8", 18),
						collateralFactor: convertToUnit("0.65", 18),
						liquidationThreshold: convertToUnit("0.7", 18),
						reserveFactor: convertToUnit("0.2", 18),
						initialSupply: convertToUnit(10_000, 18),
						supplyCap: convertToUnit(500_000, 18),
						borrowCap: convertToUnit(200_000, 18),
						leTokenReceiver: preconfiguredAddresses.sepolia.LeTreasury,
						reduceReservesBlockDelta: "100",
					},
					{
						name: "KRAI (KredlyCorePool)",
						asset: "KRAI",
						symbol: "leKRAI_KredlyCorePool",
						rateModel: InterestRateModels.JumpRate.toString(),
						baseRatePerYear: convertToUnit("0.02", 18),
						multiplierPerYear: convertToUnit("0.1", 18),
						jumpMultiplierPerYear: convertToUnit("3", 18),
						kink_: convertToUnit("0.8", 18),
						collateralFactor: convertToUnit("0.65", 18),
						liquidationThreshold: convertToUnit("0.7", 18),
						reserveFactor: convertToUnit("0.2", 18),
						initialSupply: convertToUnit(10_000, 18),
						supplyCap: convertToUnit(500_000, 18),
						borrowCap: convertToUnit(200_000, 18),
						leTokenReceiver: preconfiguredAddresses.sepolia.LeTreasury,
						reduceReservesBlockDelta: "100",
					},
					{
						name: "USDC (KredlyCorePool)",
						asset: "USDC",
						symbol: "leUSDC_KredlyCorePool",
						rateModel: InterestRateModels.JumpRate.toString(),
						baseRatePerYear: convertToUnit("0.02", 18),
						multiplierPerYear: convertToUnit("0.1", 18),
						jumpMultiplierPerYear: convertToUnit("3", 18),
						kink_: convertToUnit("0.8", 18),
						collateralFactor: convertToUnit("0.65", 18),
						liquidationThreshold: convertToUnit("0.7", 18),
						reserveFactor: convertToUnit("0.2", 18),
						initialSupply: convertToUnit(10_000, 6), // USDC has 6 decimals on testnet
						supplyCap: convertToUnit(500_000, 6), // USDC has 6 decimals on testnet
						borrowCap: convertToUnit(200_000, 6), // USDC has 6 decimals on testnet
						leTokenReceiver: preconfiguredAddresses.sepolia.LeTreasury,
						reduceReservesBlockDelta: "100",
					}
				],
				rewards: [
					// {
					// 	asset: "HAY",
					// 	markets: ["HAY"],
					// 	supplySpeeds: ["1860119047619047"], // 1500 HAY over 28 days (806400 blocks)
					// 	borrowSpeeds: ["1860119047619047"], // 1500 HAY over 28 days (806400 blocks)
					// },
				],
			}
		],
		accessControlConfig: [
			...poolRegistryPermissions()
		],
		preconfiguredAddresses: preconfiguredAddresses.sepolia,
	},
	mantle: {
		tokensConfig: [
			{
				isMock: false,
				name: "MNT",
				symbol: "MNT",
				decimals: 18,
				tokenAddress: "0x00a92853EC3084F3C52A6c6C2D744cb98b4bcAc3"
			}, {
				isMock: false,
				name: "wrappedETH",
				symbol: "WETH",
				decimals: 18,
				tokenAddress: "0x5351197Fc3bc4301F885E2085abe17C14724FdD4"
			},
			{
				isMock: false,
				name: "KRAI",
				symbol: "KRAI",
				decimals: 18,
				tokenAddress: "0x12710030e9EfDb9b085b7446C50a8aaAb3Aa7921"
			},
			{
				isMock: false,
				name: "USDC",
				symbol: "USDC",
				decimals: 6,
				tokenAddress: "0x448ca23a0C9d64fEcD4852B29Df0b3193f026300"
			}
		],
		poolConfig: [
			{
				id: "KredlyCorePool",
				name: "Kredly Core Pool",
				closeFactor: convertToUnit("0.5", 18),
				liquidationIncentive: convertToUnit("1.1", 18),
				minLiquidatableCollateral: convertToUnit("100", 18),
				letokens: [
					{
						name: "MNT (KredlyCorePool)",
						asset: "MNT",
						symbol: "leMNT_KredlyCorePool",
						rateModel: InterestRateModels.JumpRate.toString(),
						baseRatePerYear: convertToUnit("0.02", 18),
						multiplierPerYear: convertToUnit("0.1", 18),
						jumpMultiplierPerYear: convertToUnit("3", 18),
						kink_: convertToUnit("0.8", 18),
						collateralFactor: convertToUnit("0.65", 18),
						liquidationThreshold: convertToUnit("0.7", 18),
						reserveFactor: convertToUnit("0.2", 18),
						initialSupply: convertToUnit(10_000, 18),
						supplyCap: convertToUnit(500_000, 18),
						borrowCap: convertToUnit(200_000, 18),
						leTokenReceiver: preconfiguredAddresses.mantle.LeTreasury,
						reduceReservesBlockDelta: "100",
					},
					{
						name: "WETH (KredlyCorePool)",
						asset: "WETH",
						symbol: "leWETH_KredlyCorePool",
						rateModel: InterestRateModels.JumpRate.toString(),
						baseRatePerYear: convertToUnit("0.02", 18),
						multiplierPerYear: convertToUnit("0.1", 18),
						jumpMultiplierPerYear: convertToUnit("3", 18),
						kink_: convertToUnit("0.8", 18),
						collateralFactor: convertToUnit("0.65", 18),
						liquidationThreshold: convertToUnit("0.7", 18),
						reserveFactor: convertToUnit("0.2", 18),
						initialSupply: convertToUnit(10_000, 18),
						supplyCap: convertToUnit(500_000, 18),
						borrowCap: convertToUnit(200_000, 18),
						leTokenReceiver: preconfiguredAddresses.mantle.LeTreasury,
						reduceReservesBlockDelta: "100",
					},
					{
						name: "KRAI (KredlyCorePool)",
						asset: "KRAI",
						symbol: "leKRAI_KredlyCorePool",
						rateModel: InterestRateModels.JumpRate.toString(),
						baseRatePerYear: convertToUnit("0.02", 18),
						multiplierPerYear: convertToUnit("0.1", 18),
						jumpMultiplierPerYear: convertToUnit("3", 18),
						kink_: convertToUnit("0.8", 18),
						collateralFactor: convertToUnit("0.65", 18),
						liquidationThreshold: convertToUnit("0.7", 18),
						reserveFactor: convertToUnit("0.2", 18),
						initialSupply: convertToUnit(10_000, 18),
						supplyCap: convertToUnit(500_000, 18),
						borrowCap: convertToUnit(200_000, 18),
						leTokenReceiver: preconfiguredAddresses.mantle.LeTreasury,
						reduceReservesBlockDelta: "100",
					},
					{
						name: "USDC (KredlyCorePool)",
						asset: "USDC",
						symbol: "leUSDC_KredlyCorePool",
						rateModel: InterestRateModels.JumpRate.toString(),
						baseRatePerYear: convertToUnit("0.02", 18),
						multiplierPerYear: convertToUnit("0.1", 18),
						jumpMultiplierPerYear: convertToUnit("3", 18),
						kink_: convertToUnit("0.8", 18),
						collateralFactor: convertToUnit("0.65", 18),
						liquidationThreshold: convertToUnit("0.7", 18),
						reserveFactor: convertToUnit("0.2", 18),
						initialSupply: convertToUnit(10_000, 6), // USDC has 6 decimals on testnet
						supplyCap: convertToUnit(500_000, 6), // USDC has 6 decimals on testnet
						borrowCap: convertToUnit(200_000, 6), // USDC has 6 decimals on testnet
						leTokenReceiver: preconfiguredAddresses.mantle.LeTreasury,
						reduceReservesBlockDelta: "100",
					}
				],
				rewards: [
					// {
					// 	asset: "HAY",
					// 	markets: ["HAY"],
					// 	supplySpeeds: ["1860119047619047"], // 1500 HAY over 28 days (806400 blocks)
					// 	borrowSpeeds: ["1860119047619047"], // 1500 HAY over 28 days (806400 blocks)
					// },
				],
			}
		],
		accessControlConfig: [
			...poolRegistryPermissions()
		],
		preconfiguredAddresses: preconfiguredAddresses.mantle,
	},
	mantle_sepolia: {
		tokensConfig: [
			{
				isMock: false,
				name: "MNT",
				symbol: "MNT",
				decimals: 18,
				tokenAddress: "0x00a92853EC3084F3C52A6c6C2D744cb98b4bcAc3"
			}, {
				isMock: false,
				name: "wrappedETH",
				symbol: "WETH",
				decimals: 18,
				tokenAddress: "0x5351197Fc3bc4301F885E2085abe17C14724FdD4"
			},
			{
				isMock: false,
				name: "KRAI",
				symbol: "KRAI",
				decimals: 18,
				tokenAddress: "0x12710030e9EfDb9b085b7446C50a8aaAb3Aa7921"
			},
			{
				isMock: false,
				name: "USDC",
				symbol: "USDC",
				decimals: 6,
				tokenAddress: "0x448ca23a0C9d64fEcD4852B29Df0b3193f026300"
			}
		],
		poolConfig: [
			{
				id: "KredlyCorePool",
				name: "Kredly Core Pool",
				closeFactor: convertToUnit("0.5", 18),
				liquidationIncentive: convertToUnit("1.1", 18),
				minLiquidatableCollateral: convertToUnit("100", 18),
				letokens: [
					{
						name: "MNT (KredlyCorePool)",
						asset: "MNT",
						symbol: "leMNT_KredlyCorePool",
						rateModel: InterestRateModels.JumpRate.toString(),
						baseRatePerYear: convertToUnit("0.02", 18),
						multiplierPerYear: convertToUnit("0.1", 18),
						jumpMultiplierPerYear: convertToUnit("3", 18),
						kink_: convertToUnit("0.8", 18),
						collateralFactor: convertToUnit("0.65", 18),
						liquidationThreshold: convertToUnit("0.7", 18),
						reserveFactor: convertToUnit("0.2", 18),
						initialSupply: convertToUnit(10_000, 18),
						supplyCap: convertToUnit(500_000, 18),
						borrowCap: convertToUnit(200_000, 18),
						leTokenReceiver: preconfiguredAddresses.mantle_sepolia.LeTreasury,
						reduceReservesBlockDelta: "100",
					},
					{
						name: "WETH (KredlyCorePool)",
						asset: "WETH",
						symbol: "leWETH_KredlyCorePool",
						rateModel: InterestRateModels.JumpRate.toString(),
						baseRatePerYear: convertToUnit("0.02", 18),
						multiplierPerYear: convertToUnit("0.1", 18),
						jumpMultiplierPerYear: convertToUnit("3", 18),
						kink_: convertToUnit("0.8", 18),
						collateralFactor: convertToUnit("0.65", 18),
						liquidationThreshold: convertToUnit("0.7", 18),
						reserveFactor: convertToUnit("0.2", 18),
						initialSupply: convertToUnit(10_000, 18),
						supplyCap: convertToUnit(500_000, 18),
						borrowCap: convertToUnit(200_000, 18),
						leTokenReceiver: preconfiguredAddresses.mantle_sepolia.LeTreasury,
						reduceReservesBlockDelta: "100",
					},
					{
						name: "KRAI (KredlyCorePool)",
						asset: "KRAI",
						symbol: "leKRAI_KredlyCorePool",
						rateModel: InterestRateModels.JumpRate.toString(),
						baseRatePerYear: convertToUnit("0.02", 18),
						multiplierPerYear: convertToUnit("0.1", 18),
						jumpMultiplierPerYear: convertToUnit("3", 18),
						kink_: convertToUnit("0.8", 18),
						collateralFactor: convertToUnit("0.65", 18),
						liquidationThreshold: convertToUnit("0.7", 18),
						reserveFactor: convertToUnit("0.2", 18),
						initialSupply: convertToUnit(10_000, 18),
						supplyCap: convertToUnit(500_000, 18),
						borrowCap: convertToUnit(200_000, 18),
						leTokenReceiver: preconfiguredAddresses.mantle_sepolia.LeTreasury,
						reduceReservesBlockDelta: "100",
					},
					{
						name: "USDC (KredlyCorePool)",
						asset: "USDC",
						symbol: "leUSDC_KredlyCorePool",
						rateModel: InterestRateModels.JumpRate.toString(),
						baseRatePerYear: convertToUnit("0.02", 18),
						multiplierPerYear: convertToUnit("0.1", 18),
						jumpMultiplierPerYear: convertToUnit("3", 18),
						kink_: convertToUnit("0.8", 18),
						collateralFactor: convertToUnit("0.65", 18),
						liquidationThreshold: convertToUnit("0.7", 18),
						reserveFactor: convertToUnit("0.2", 18),
						initialSupply: convertToUnit(10_000, 6), // USDC has 6 decimals on testnet
						supplyCap: convertToUnit(500_000, 6), // USDC has 6 decimals on testnet
						borrowCap: convertToUnit(200_000, 6), // USDC has 6 decimals on testnet
						leTokenReceiver: preconfiguredAddresses.mantle_sepolia.LeTreasury,
						reduceReservesBlockDelta: "100",
					}
				],
				rewards: [
					// {
					// 	asset: "HAY",
					// 	markets: ["HAY"],
					// 	supplySpeeds: ["1860119047619047"], // 1500 HAY over 28 days (806400 blocks)
					// 	borrowSpeeds: ["1860119047619047"], // 1500 HAY over 28 days (806400 blocks)
					// },
				],
			}
		],
		accessControlConfig: [
			...poolRegistryPermissions()
		],
		preconfiguredAddresses: preconfiguredAddresses.mantle_sepolia,
	},
};

const getTokenConfig = (tokenSymbol: string, tokens: TokenConfig[]): TokenConfig => {
	const tokenCofig = tokens.find(
		({ symbol }) => symbol.toLocaleLowerCase().trim() === tokenSymbol.toLocaleLowerCase().trim(),
	)

	if (tokenCofig) {
		return tokenCofig;
	} else {
		throw Error(`Token ${tokenSymbol} is not found in the config`);
	}
}

const getTokenAddress = async (tokenConfig: TokenConfig, deployments: DeploymentsExtension) => {
	if (tokenConfig.isMock) {
		const token = await deployments.get(`Mock${tokenConfig.symbol}`);
		return token.address;
	} else {
		return tokenConfig.tokenAddress;
	}
}

export {
	globalConfig,
	getTokenConfig,
	getTokenAddress,
	BLOCKS_PER_YEAR,
	InterestRateModels
}