import hre, { deployments, ethers, getNamedAccounts, network } from "hardhat";
import { ANY_CONTRACT, getTokenConfig, globalConfig } from "../helpers/deploymentConfig";
import { getUnregisteredPools, toAddress } from "../helpers/deploymentUtils";


const givePermissions = async (preconfiguredAddresses, permissions: { target: string, methods: string[], caller: string }) => {

    const accessControlManagerAddress = await toAddress(
        preconfiguredAddresses.AccessControlManager || "AccessControlManager",
        hre,
    );
    let accessControlManager = await ethers.getContractAt("AccessControlManager", accessControlManagerAddress);
    for (const method of permissions.methods) {
        let tx = await accessControlManager.giveCallPermission(permissions.target, method, permissions.caller);
        await tx.wait();
    }
}

describe("register comptollers and markets to pool registry", () => {
    before(async function () {
        this.deploy = deployments.deploy;
        this.deployer = (await getNamedAccounts()).deployer;
    });

    it("give permission for pool registry", async function () {
        const { preconfiguredAddresses } = globalConfig[network.name];
        const poolRegistry = await ethers.getContract(`PoolRegistry`);
        // give call permission for pool registry
        let methods = [
            "swapPoolsAssets(address[],uint256[],address[][])",
            "addPool(string,address,uint256,uint256,uint256)",
            "addMarket(AddMarketInput)",
            "setRewardTokenSpeeds(address[],uint256[],uint256[])",
            "setReduceReservesBlockDelta(uint256)",
        ];
        await givePermissions(
            preconfiguredAddresses,
            {
                target: poolRegistry.address,
                methods: methods,
                caller: this.deployer
            })
    })

    it("give permission to pool registry", async function () {
        const { preconfiguredAddresses } = globalConfig[network.name];
        const poolRegistry = await ethers.getContract(`PoolRegistry`);

        // give call permission for comptoller
        const methods = [
            "setCollateralFactor(address,uint256,uint256)",
            "setMarketSupplyCaps(address[],uint256[])",
            "setMarketBorrowCaps(address[],uint256[])",
            "setLiquidationIncentive(uint256)",
            "setCloseFactor(uint256)",
            "setMinLiquidatableCollateral(uint256)",
            "supportMarket(address)",
        ];
        await givePermissions(
            preconfiguredAddresses,
            {
                target: ANY_CONTRACT,
                methods: methods,
                caller: poolRegistry.address
            })
    })

    it("register pool", async function () {
        const { poolConfig, preconfiguredAddresses } = globalConfig[network.name];
        const unregisteredPools = await getUnregisteredPools(poolConfig, hre);

        const poolRegistry = await ethers.getContract(`PoolRegistry`);
        const priceOracleAddress = await toAddress(
            preconfiguredAddresses.priceOracle || "mockPriceOracle",
            hre,
        );

        for (const pool of unregisteredPools) {
            const comptollerAddress = (await ethers.getContract(`Comptroller_${pool.id}`)).address;
            const comptoller = await ethers.getContractAt("Comptroller", comptollerAddress);

            console.log(`register Comptroller_${pool.id}`);
            // set oracle 
            var tx = await comptoller.setPriceOracle(priceOracleAddress);
            await tx.wait();

            // register comptoller
            var tx = await poolRegistry.addPool(
                pool.name,
                comptoller.address,
                pool.closeFactor,
                pool.liquidationIncentive,
                pool.minLiquidatableCollateral,
            );
            await tx.wait();
        }
    })

    it("register markets", async function () {
        const { tokensConfig, poolConfig } = globalConfig[network.name];
        const poolRegistry = await ethers.getContract(`PoolRegistry`);

        const unregisteredPools = await getUnregisteredPools(poolConfig, hre);
        for (const pool of unregisteredPools) {
            // Deploy Markets
            for (const letoken of pool.letokens) {
                const { asset } = letoken;

                const token = getTokenConfig(asset, tokensConfig);
                {
                    let tokenContract;
                    if (token.isMock) {
                        tokenContract = await ethers.getContract(`Mock${token.symbol}`);
                    } else {
                        tokenContract = await ethers.getContractAt("@openzeppelin/contracts/token/ERC20/ERC20.sol:ERC20", token.tokenAddress)
                    }
                    var tx = await tokenContract.approve(poolRegistry.address, letoken.initialSupply);
                    await tx.wait();
                }

                const leTokenContract = await ethers.getContract(`LeToken_${letoken.symbol}`);
                try {
                    var tx = await poolRegistry.addMarket({
                        leToken: leTokenContract.address,
                        collateralFactor: letoken.collateralFactor,
                        liquidationThreshold: letoken.liquidationThreshold,
                        initialSupply: letoken.initialSupply,
                        leTokenReceiver: toAddress(letoken.leTokenReceiver, hre),
                        supplyCap: letoken.supplyCap,
                        borrowCap: letoken.borrowCap
                    });
                    await tx.wait()
                } catch (error) {
                    console.log("add market error", error.message);
                }
            }
        }
    })
})