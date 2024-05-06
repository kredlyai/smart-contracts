// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.13;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { ResilientOracleInterface } from "../access-controll/interfaces/OracleInterface.sol";

import { ExponentialNoError } from "../ExponentialNoError.sol";
import { LeToken } from "../LeToken.sol";
import { Action, ComptrollerInterface, ComptrollerViewInterface } from "../ComptrollerInterface.sol";
import { PoolRegistryInterface } from "../Pool/PoolRegistryInterface.sol";
import { PoolRegistry } from "../Pool/PoolRegistry.sol";
import { RewardsDistributor } from "../Rewards/RewardsDistributor.sol";

/**
 * @title PoolLens
 * @author Kredly
 * @notice The `PoolLens` contract is designed to retrieve important information for each registered pool. A list of essential information
 * for all pools within the lending protocol can be acquired through the function `getAllPools()`. Additionally, the following records can be
 * looked up for specific pools and markets:
- the leToken balance of a given user;
- the pool data (oracle address, associated leToken, liquidation incentive, etc) of a pool via its associated comptroller address;
- the leToken address in a pool for a given asset;
- a list of all pools that support an asset;
- the underlying asset price of a leToken;
- the metadata (exchange/borrow/supply rate, total supply, collateral factor, etc) of any leToken.
 */
contract PoolLens is ExponentialNoError {
    /**
     * @dev Struct for PoolDetails.
     */
    struct PoolData {
        string name;
        address creator;
        address comptroller;
        uint256 blockPosted;
        uint256 timestampPosted;
        string category;
        string logoURL;
        string description;
        address priceOracle;
        uint256 closeFactor;
        uint256 liquidationIncentive;
        uint256 minLiquidatableCollateral;
        LeTokenMetadata[] leTokens;
    }

    /**
     * @dev Struct for LeToken.
     */
    struct LeTokenMetadata {
        address leToken;
        uint256 exchangeRateCurrent;
        uint256 supplyRatePerBlock;
        uint256 borrowRatePerBlock;
        uint256 reserveFactorMantissa;
        uint256 supplyCaps;
        uint256 borrowCaps;
        uint256 totalBorrows;
        uint256 totalReserves;
        uint256 totalSupply;
        uint256 totalCash;
        bool isListed;
        uint256 collateralFactorMantissa;
        address underlyingAssetAddress;
        uint256 leTokenDecimals;
        uint256 underlyingDecimals;
        uint256 pausedActions;
    }

    /**
     * @dev Struct for LeTokenBalance.
     */
    struct LeTokenBalances {
        address leToken;
        uint256 balanceOf;
        uint256 borrowBalanceCurrent;
        uint256 balanceOfUnderlying;
        uint256 tokenBalance;
        uint256 tokenAllowance;
    }

    /**
     * @dev Struct for underlyingPrice of LeToken.
     */
    struct LeTokenUnderlyingPrice {
        address leToken;
        uint256 underlyingPrice;
    }

    /**
     * @dev Struct with pending reward info for a market.
     */
    struct PendingReward {
        address leTokenAddress;
        uint256 amount;
    }

    /**
     * @dev Struct with reward distribution totals for a single reward token and distributor.
     */
    struct RewardSummary {
        address distributorAddress;
        address rewardTokenAddress;
        uint256 totalRewards;
        PendingReward[] pendingRewards;
    }

    /**
     * @dev Struct used in RewardDistributor to save last updated market state.
     */
    struct RewardTokenState {
        // The market's last updated rewardTokenBorrowIndex or rewardTokenSupplyIndex
        uint224 index;
        // The block number the index was last updated at
        uint32 block;
        // The block number at which to stop rewards
        uint32 lastRewardingBlock;
    }

    /**
     * @dev Struct with bad debt of a market denominated
     */
    struct BadDebt {
        address leTokenAddress;
        uint256 badDebtUsd;
    }

    /**
     * @dev Struct with bad debt total denominated in usd for a pool and an array of BadDebt structs for each market
     */
    struct BadDebtSummary {
        address comptroller;
        uint256 totalBadDebtUsd;
        BadDebt[] badDebts;
    }

    /**
     * @notice Queries the user's supply/borrow balances in leTokens
     * @param leTokens The list of leToken addresses
     * @param account The user Account
     * @return A list of structs containing balances data
     */
    function leTokenBalancesAll(LeToken[] calldata leTokens, address account) external returns (LeTokenBalances[] memory) {
        uint256 leTokenCount = leTokens.length;
        LeTokenBalances[] memory res = new LeTokenBalances[](leTokenCount);
        for (uint256 i; i < leTokenCount; ++i) {
            res[i] = leTokenBalances(leTokens[i], account);
        }
        return res;
    }

    /**
     * @notice Queries all pools with addtional details for each of them
     * @dev This function is not designed to be called in a transaction: it is too gas-intensive
     * @param poolRegistryAddress The address of the PoolRegistry contract
     * @return Arrays of all Kredly pools' data
     */
    function getAllPools(address poolRegistryAddress) external view returns (PoolData[] memory) {
        PoolRegistryInterface poolRegistryInterface = PoolRegistryInterface(poolRegistryAddress);
        PoolRegistry.KredlyPool[] memory kredlyPools = poolRegistryInterface.getAllPools();
        uint256 poolLength = kredlyPools.length;

        PoolData[] memory poolDataItems = new PoolData[](poolLength);

        for (uint256 i; i < poolLength; ++i) {
            PoolRegistry.KredlyPool memory kredlyPool = kredlyPools[i];
            PoolData memory poolData = getPoolDataFromkredlyPool(poolRegistryAddress, kredlyPool);
            poolDataItems[i] = poolData;
        }

        return poolDataItems;
    }

    /**
     * @notice Queries the details of a pool identified by Comptroller address
     * @param poolRegistryAddress The address of the PoolRegistry contract
     * @param comptroller The Comptroller implementation address
     * @return PoolData structure containing the details of the pool
     */
    function getPoolByComptroller(
        address poolRegistryAddress,
        address comptroller
    ) external view returns (PoolData memory) {
        PoolRegistryInterface poolRegistryInterface = PoolRegistryInterface(poolRegistryAddress);
        return getPoolDataFromkredlyPool(poolRegistryAddress, poolRegistryInterface.getPoolByComptroller(comptroller));
    }

    /**
     * @notice Returns leToken holding the specified underlying asset in the specified pool
     * @param poolRegistryAddress The address of the PoolRegistry contract
     * @param comptroller The pool comptroller
     * @param asset The underlyingAsset of LeToken
     * @return Address of the leToken
     */
    function getLeTokenForAsset(
        address poolRegistryAddress,
        address comptroller,
        address asset
    ) external view returns (address) {
        PoolRegistryInterface poolRegistryInterface = PoolRegistryInterface(poolRegistryAddress);
        return poolRegistryInterface.getLeTokenForAsset(comptroller, asset);
    }

    /**
     * @notice Returns all pools that support the specified underlying asset
     * @param poolRegistryAddress The address of the PoolRegistry contract
     * @param asset The underlying asset of leToken
     * @return A list of Comptroller contracts
     */
    function getPoolsSupportedByAsset(
        address poolRegistryAddress,
        address asset
    ) external view returns (address[] memory) {
        PoolRegistryInterface poolRegistryInterface = PoolRegistryInterface(poolRegistryAddress);
        return poolRegistryInterface.getPoolsSupportedByAsset(asset);
    }

    /**
     * @notice Returns the price data for the underlying assets of the specified leTokens
     * @param leTokens The list of leToken addresses
     * @return An array containing the price data for each asset
     */
    function leTokenUnderlyingPriceAll(
        LeToken[] calldata leTokens
    ) external view returns (LeTokenUnderlyingPrice[] memory) {
        uint256 leTokenCount = leTokens.length;
        LeTokenUnderlyingPrice[] memory res = new LeTokenUnderlyingPrice[](leTokenCount);
        for (uint256 i; i < leTokenCount; ++i) {
            res[i] = leTokenUnderlyingPrice(leTokens[i]);
        }
        return res;
    }

    /**
     * @notice Returns the pending rewards for a user for a given pool.
     * @param account The user account.
     * @param comptrollerAddress address
     * @return Pending rewards array
     */
    function getPendingRewards(
        address account,
        address comptrollerAddress
    ) external view returns (RewardSummary[] memory) {
        LeToken[] memory markets = ComptrollerInterface(comptrollerAddress).getAllMarkets();
        RewardsDistributor[] memory rewardsDistributors = ComptrollerViewInterface(comptrollerAddress)
            .getRewardDistributors();
        RewardSummary[] memory rewardSummary = new RewardSummary[](rewardsDistributors.length);
        for (uint256 i; i < rewardsDistributors.length; ++i) {
            RewardSummary memory reward;
            reward.distributorAddress = address(rewardsDistributors[i]);
            reward.rewardTokenAddress = address(rewardsDistributors[i].rewardToken());
            reward.totalRewards = rewardsDistributors[i].rewardTokenAccrued(account);
            reward.pendingRewards = _calculateNotDistributedAwards(account, markets, rewardsDistributors[i]);
            rewardSummary[i] = reward;
        }
        return rewardSummary;
    }

    /**
     * @notice Returns a summary of a pool's bad debt broken down by market
     *
     * @param comptrollerAddress Address of the comptroller
     *
     * @return badDebtSummary A struct with comptroller address, total bad debut denominated in usd, and
     *   a break down of bad debt by market
     */
    function getPoolBadDebt(address comptrollerAddress) external view returns (BadDebtSummary memory) {
        uint256 totalBadDebtUsd;

        // Get every market in the pool
        ComptrollerViewInterface comptroller = ComptrollerViewInterface(comptrollerAddress);
        LeToken[] memory markets = comptroller.getAllMarkets();
        ResilientOracleInterface priceOracle = comptroller.oracle();

        BadDebt[] memory badDebts = new BadDebt[](markets.length);

        BadDebtSummary memory badDebtSummary;
        badDebtSummary.comptroller = comptrollerAddress;
        badDebtSummary.badDebts = badDebts;

        // // Calculate the bad debt is USD per market
        for (uint256 i; i < markets.length; ++i) {
            BadDebt memory badDebt;
            badDebt.leTokenAddress = address(markets[i]);
            badDebt.badDebtUsd =
                (LeToken(address(markets[i])).badDebt() * priceOracle.getUnderlyingPrice(address(markets[i]))) /
                EXP_SCALE;
            badDebtSummary.badDebts[i] = badDebt;
            totalBadDebtUsd = totalBadDebtUsd + badDebt.badDebtUsd;
        }

        badDebtSummary.totalBadDebtUsd = totalBadDebtUsd;

        return badDebtSummary;
    }

    /**
     * @notice Queries the user's supply/borrow balances in the specified leToken
     * @param leToken leToken address
     * @param account The user Account
     * @return A struct containing the balances data
     */
    function leTokenBalances(LeToken leToken, address account) public returns (LeTokenBalances memory) {
        uint256 balanceOf = leToken.balanceOf(account);
        uint256 borrowBalanceCurrent = leToken.borrowBalanceCurrent(account);
        uint256 balanceOfUnderlying = leToken.balanceOfUnderlying(account);
        uint256 tokenBalance;
        uint256 tokenAllowance;

        IERC20 underlying = IERC20(leToken.underlying());
        tokenBalance = underlying.balanceOf(account);
        tokenAllowance = underlying.allowance(account, address(leToken));

        return
            LeTokenBalances({
                leToken: address(leToken),
                balanceOf: balanceOf,
                borrowBalanceCurrent: borrowBalanceCurrent,
                balanceOfUnderlying: balanceOfUnderlying,
                tokenBalance: tokenBalance,
                tokenAllowance: tokenAllowance
            });
    }

    /**
     * @notice Queries additional information for the pool
     * @param poolRegistryAddress Address of the PoolRegistry
     * @param kredlyPool The KredlyPool Object from PoolRegistry
     * @return Enriched PoolData
     */
    function getPoolDataFromkredlyPool(
        address poolRegistryAddress,
        PoolRegistry.KredlyPool memory kredlyPool
    ) public view returns (PoolData memory) {
        // Get tokens in the Pool
        ComptrollerInterface comptrollerInstance = ComptrollerInterface(kredlyPool.comptroller);

        LeToken[] memory leTokens = comptrollerInstance.getAllMarkets();

        LeTokenMetadata[] memory leTokenMetadataItems = leTokenMetadataAll(leTokens);

        PoolRegistryInterface poolRegistryInterface = PoolRegistryInterface(poolRegistryAddress);

        PoolRegistry.kredlyPoolMetaData memory kredlyPoolMetaData = poolRegistryInterface.getkredlyPoolMetadata(
            kredlyPool.comptroller
        );

        ComptrollerViewInterface comptrollerViewInstance = ComptrollerViewInterface(kredlyPool.comptroller);

        PoolData memory poolData = PoolData({
            name: kredlyPool.name,
            creator: kredlyPool.creator,
            comptroller: kredlyPool.comptroller,
            blockPosted: kredlyPool.blockPosted,
            timestampPosted: kredlyPool.timestampPosted,
            category: kredlyPoolMetaData.category,
            logoURL: kredlyPoolMetaData.logoURL,
            description: kredlyPoolMetaData.description,
            leTokens: leTokenMetadataItems,
            priceOracle: address(comptrollerViewInstance.oracle()),
            closeFactor: comptrollerViewInstance.closeFactorMantissa(),
            liquidationIncentive: comptrollerViewInstance.liquidationIncentiveMantissa(),
            minLiquidatableCollateral: comptrollerViewInstance.minLiquidatableCollateral()
        });

        return poolData;
    }

    /**
     * @notice Returns the metadata of LeToken
     * @param leToken The address of leToken
     * @return LeTokenMetadata struct
     */
    function leTokenMetadata(LeToken leToken) public view returns (LeTokenMetadata memory) {
        uint256 exchangeRateCurrent = leToken.exchangeRateStored();
        address comptrollerAddress = address(leToken.comptroller());
        ComptrollerViewInterface comptroller = ComptrollerViewInterface(comptrollerAddress);
        (bool isListed, uint256 collateralFactorMantissa) = comptroller.markets(address(leToken));

        address underlyingAssetAddress = leToken.underlying();
        uint256 underlyingDecimals = IERC20Metadata(underlyingAssetAddress).decimals();

        uint256 pausedActions;
        for (uint8 i; i <= uint8(type(Action).max); ++i) {
            uint256 paused = ComptrollerInterface(comptrollerAddress).actionPaused(address(leToken), Action(i)) ? 1 : 0;
            pausedActions |= paused << i;
        }

        return
            LeTokenMetadata({
                leToken: address(leToken),
                exchangeRateCurrent: exchangeRateCurrent,
                supplyRatePerBlock: leToken.supplyRatePerBlock(),
                borrowRatePerBlock: leToken.borrowRatePerBlock(),
                reserveFactorMantissa: leToken.reserveFactorMantissa(),
                supplyCaps: comptroller.supplyCaps(address(leToken)),
                borrowCaps: comptroller.borrowCaps(address(leToken)),
                totalBorrows: leToken.totalBorrows(),
                totalReserves: leToken.totalReserves(),
                totalSupply: leToken.totalSupply(),
                totalCash: leToken.getCash(),
                isListed: isListed,
                collateralFactorMantissa: collateralFactorMantissa,
                underlyingAssetAddress: underlyingAssetAddress,
                leTokenDecimals: leToken.decimals(),
                underlyingDecimals: underlyingDecimals,
                pausedActions: pausedActions
            });
    }

    /**
     * @notice Returns the metadata of all LeTokens
     * @param leTokens The list of leToken addresses
     * @return An array of LeTokenMetadata structs
     */
    function leTokenMetadataAll(LeToken[] memory leTokens) public view returns (LeTokenMetadata[] memory) {
        uint256 leTokenCount = leTokens.length;
        LeTokenMetadata[] memory res = new LeTokenMetadata[](leTokenCount);
        for (uint256 i; i < leTokenCount; ++i) {
            res[i] = leTokenMetadata(leTokens[i]);
        }
        return res;
    }

    /**
     * @notice Returns the price data for the underlying asset of the specified leToken
     * @param leToken leToken address
     * @return The price data for each asset
     */
    function leTokenUnderlyingPrice(LeToken leToken) public view returns (LeTokenUnderlyingPrice memory) {
        ComptrollerViewInterface comptroller = ComptrollerViewInterface(address(leToken.comptroller()));
        ResilientOracleInterface priceOracle = comptroller.oracle();

        return
            LeTokenUnderlyingPrice({
                leToken: address(leToken),
                underlyingPrice: priceOracle.getUnderlyingPrice(address(leToken))
            });
    }

    function _calculateNotDistributedAwards(
        address account,
        LeToken[] memory markets,
        RewardsDistributor rewardsDistributor
    ) internal view returns (PendingReward[] memory) {
        PendingReward[] memory pendingRewards = new PendingReward[](markets.length);
        for (uint256 i; i < markets.length; ++i) {
            // Market borrow and supply state we will modify update in-memory, in order to not modify storage
            RewardTokenState memory borrowState;
            (borrowState.index, borrowState.block, borrowState.lastRewardingBlock) = rewardsDistributor
                .rewardTokenBorrowState(address(markets[i]));
            RewardTokenState memory supplyState;
            (supplyState.index, supplyState.block, supplyState.lastRewardingBlock) = rewardsDistributor
                .rewardTokenSupplyState(address(markets[i]));
            Exp memory marketBorrowIndex = Exp({ mantissa: markets[i].borrowIndex() });

            // Update market supply and borrow index in-memory
            updateMarketBorrowIndex(address(markets[i]), rewardsDistributor, borrowState, marketBorrowIndex);
            updateMarketSupplyIndex(address(markets[i]), rewardsDistributor, supplyState);

            // Calculate pending rewards
            uint256 borrowReward = calculateBorrowerReward(
                address(markets[i]),
                rewardsDistributor,
                account,
                borrowState,
                marketBorrowIndex
            );
            uint256 supplyReward = calculateSupplierReward(
                address(markets[i]),
                rewardsDistributor,
                account,
                supplyState
            );

            PendingReward memory pendingReward;
            pendingReward.leTokenAddress = address(markets[i]);
            pendingReward.amount = borrowReward + supplyReward;
            pendingRewards[i] = pendingReward;
        }
        return pendingRewards;
    }

    function updateMarketBorrowIndex(
        address leToken,
        RewardsDistributor rewardsDistributor,
        RewardTokenState memory borrowState,
        Exp memory marketBorrowIndex
    ) internal view {
        uint256 borrowSpeed = rewardsDistributor.rewardTokenBorrowSpeeds(leToken);
        uint256 blockNumber = block.number;

        if (borrowState.lastRewardingBlock > 0 && blockNumber > borrowState.lastRewardingBlock) {
            blockNumber = borrowState.lastRewardingBlock;
        }

        uint256 deltaBlocks = sub_(blockNumber, uint256(borrowState.block));
        if (deltaBlocks > 0 && borrowSpeed > 0) {
            // Remove the total earned interest rate since the opening of the market from total borrows
            uint256 borrowAmount = div_(LeToken(leToken).totalBorrows(), marketBorrowIndex);
            uint256 tokensAccrued = mul_(deltaBlocks, borrowSpeed);
            Double memory ratio = borrowAmount > 0 ? fraction(tokensAccrued, borrowAmount) : Double({ mantissa: 0 });
            Double memory index = add_(Double({ mantissa: borrowState.index }), ratio);
            borrowState.index = safe224(index.mantissa, "new index overflows");
            borrowState.block = safe32(blockNumber, "block number overflows");
        } else if (deltaBlocks > 0) {
            borrowState.block = safe32(blockNumber, "block number overflows");
        }
    }

    function updateMarketSupplyIndex(
        address leToken,
        RewardsDistributor rewardsDistributor,
        RewardTokenState memory supplyState
    ) internal view {
        uint256 supplySpeed = rewardsDistributor.rewardTokenSupplySpeeds(leToken);
        uint256 blockNumber = block.number;

        if (supplyState.lastRewardingBlock > 0 && blockNumber > supplyState.lastRewardingBlock) {
            blockNumber = supplyState.lastRewardingBlock;
        }

        uint256 deltaBlocks = sub_(blockNumber, uint256(supplyState.block));
        if (deltaBlocks > 0 && supplySpeed > 0) {
            uint256 supplyTokens = LeToken(leToken).totalSupply();
            uint256 tokensAccrued = mul_(deltaBlocks, supplySpeed);
            Double memory ratio = supplyTokens > 0 ? fraction(tokensAccrued, supplyTokens) : Double({ mantissa: 0 });
            Double memory index = add_(Double({ mantissa: supplyState.index }), ratio);
            supplyState.index = safe224(index.mantissa, "new index overflows");
            supplyState.block = safe32(blockNumber, "block number overflows");
        } else if (deltaBlocks > 0) {
            supplyState.block = safe32(blockNumber, "block number overflows");
        }
    }

    function calculateBorrowerReward(
        address leToken,
        RewardsDistributor rewardsDistributor,
        address borrower,
        RewardTokenState memory borrowState,
        Exp memory marketBorrowIndex
    ) internal view returns (uint256) {
        Double memory borrowIndex = Double({ mantissa: borrowState.index });
        Double memory borrowerIndex = Double({
            mantissa: rewardsDistributor.rewardTokenBorrowerIndex(leToken, borrower)
        });
        if (borrowerIndex.mantissa == 0 && borrowIndex.mantissa >= rewardsDistributor.INITIAL_INDEX()) {
            // Covers the case where users borrowed tokens before the market's borrow state index was set
            borrowerIndex.mantissa = rewardsDistributor.INITIAL_INDEX();
        }
        Double memory deltaIndex = sub_(borrowIndex, borrowerIndex);
        uint256 borrowerAmount = div_(LeToken(leToken).borrowBalanceStored(borrower), marketBorrowIndex);
        uint256 borrowerDelta = mul_(borrowerAmount, deltaIndex);
        return borrowerDelta;
    }

    function calculateSupplierReward(
        address leToken,
        RewardsDistributor rewardsDistributor,
        address supplier,
        RewardTokenState memory supplyState
    ) internal view returns (uint256) {
        Double memory supplyIndex = Double({ mantissa: supplyState.index });
        Double memory supplierIndex = Double({
            mantissa: rewardsDistributor.rewardTokenSupplierIndex(leToken, supplier)
        });
        if (supplierIndex.mantissa == 0 && supplyIndex.mantissa >= rewardsDistributor.INITIAL_INDEX()) {
            // Covers the case where users supplied tokens before the market's supply state index was set
            supplierIndex.mantissa = rewardsDistributor.INITIAL_INDEX();
        }
        Double memory deltaIndex = sub_(supplyIndex, supplierIndex);
        uint256 supplierTokens = LeToken(leToken).balanceOf(supplier);
        uint256 supplierDelta = mul_(supplierTokens, deltaIndex);
        return supplierDelta;
    }
}
