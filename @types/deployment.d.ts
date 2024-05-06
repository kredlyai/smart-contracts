interface NetworkAddress {
	[key: string]: string;
}

interface PreconfiguredAddresses {
	[key: string]: NetworkAddress;
}

interface DeploymentConfig {
	tokensConfig: TokenConfig[]
	poolConfig: PoolConfig[]
	accessControlConfig: AccessControlEntry[]
	preconfiguredAddresses: NetworkAddress
}

interface TokenConfig {
	isMock: boolean
	name?: string
	symbol: string
	decimals?: number
	tokenAddress: string
	faucetInitialLiquidity?: boolean
}

interface PoolConfig {
	id: string
	name: string
	closeFactor: string
	liquidationIncentive: string
	minLiquidatableCollateral: string
	letokens: LeTokenConfig[]
	rewards?: RewardConfig[]
}

// NOTE: markets, supplySpeeds, borrowSpeeds array sizes should match
interface RewardConfig {
	asset: string
	markets: string[] // underlying asset symbol of a the e.g ["BNX","CAKE"]
	supplySpeeds: string[]
	borrowSpeeds: string[]
}

interface SpeedConfig {
	borrowSpeed: string
	supplySpeed: string
}

interface LeTokenConfig {
	name: string
	symbol: string
	asset: string // This should match a name property from a TokenCofig
	rateModel: string
	baseRatePerYear: string
	multiplierPerYear: string
	jumpMultiplierPerYear: string
	kink_: string
	collateralFactor: string
	liquidationThreshold: string
	reserveFactor: string
	initialSupply: string
	supplyCap: string
	borrowCap: string
	leTokenReceiver: string
	reduceReservesBlockDelta: string
}

interface AccessControlEntry {
	caller: string
	target: string
	method: string
}