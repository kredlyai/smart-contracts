// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.13;

import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

import {IPrime} from "./access-controll/IPrime.sol";
import {AccessControlledV8} from "./access-controll/AccessControlledV8.sol";
import {ResilientOracleInterface} from "./access-controll/interfaces/OracleInterface.sol";

import {ComptrollerInterface, Action} from "./ComptrollerInterface.sol";
import {ComptrollerStorage} from "./ComptrollerStorage.sol";
import {ExponentialNoError} from "./ExponentialNoError.sol";
import {LeToken} from "./LeToken.sol";
import {RewardsDistributor} from "./Rewards/RewardsDistributor.sol";
import {MaxLoopsLimitHelper} from "./MaxLoopsLimitHelper.sol";
import {ensureNonzeroAddress} from "./lib/validators.sol";

/**
 * @title Comptroller
 * @author Kredly
 * @notice The Comptroller is designed to provide checks for all minting, redeeming, transferring, borrowing, lending, repaying, liquidating,
 * and seizing done by the `leToken` contract. Each pool has one `Comptroller` checking these interactions across markets. When a user interacts
 * with a given market by one of these main actions, a call is made to a corresponding hook in the associated `Comptroller`, which either allows
 * or reverts the transaction. These hooks also update supply and borrow rewards as they are called. The comptroller holds the logic for assessing
 * liquidity snapshots of an account via the collateral factor and liquidation threshold. This check determines the collateral needed for a borrow,
 * as well as how much of a borrow may be liquidated. A user may borrow a portion of their collateral with the maximum amount determined by the
 * markets collateral factor. However, if their borrowed amount exceeds an amount calculated using the market’s corresponding liquidation threshold,
 * the borrow is eligible for liquidation.
 *
 * The `Comptroller` also includes two functions `liquidateAccount()` and `healAccount()`, which are meant to handle accounts that do not exceed
 * the `minLiquidatableCollateral` for the `Comptroller`:
 *
 * - `healAccount()`: This function is called to seize all of a given user’s collateral, requiring the `msg.sender` repay a certain percentage
 * of the debt calculated by `collateral/(borrows*liquidationIncentive)`. The function can only be called if the calculated percentage does not exceed
 * 100%, because otherwise no `badDebt` would be created and `liquidateAccount()` should be used instead. The difference in the actual amount of debt
 * and debt paid off is recorded as `badDebt` for each market, which can then be auctioned off for the risk reserves of the associated pool.
 * - `liquidateAccount()`: This function can only be called if the collateral seized will cover all borrows of an account, as well as the liquidation
 * incentive. Otherwise, the pool will incur bad debt, in which case the function `healAccount()` should be used instead. This function skips the logic
 * verifying that the repay amount does not exceed the close factor.
 */
contract Comptroller is
    Ownable2StepUpgradeable,
    AccessControlledV8,
    ComptrollerStorage,
    ComptrollerInterface,
    ExponentialNoError,
    MaxLoopsLimitHelper
{
    // PoolRegistry, immutable to save on gas
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    address public immutable poolRegistry;

    /// @notice Emitted when an account enters a market
    event MarketEntered(LeToken indexed leToken, address indexed account);

    /// @notice Emitted when an account exits a market
    event MarketExited(LeToken indexed leToken, address indexed account);

    /// @notice Emitted when close factor is changed by admin
    event NewCloseFactor(
        uint256 oldCloseFactorMantissa,
        uint256 newCloseFactorMantissa
    );

    /// @notice Emitted when a collateral factor is changed by admin
    event NewCollateralFactor(
        LeToken leToken,
        uint256 oldCollateralFactorMantissa,
        uint256 newCollateralFactorMantissa
    );

    /// @notice Emitted when liquidation threshold is changed by admin
    event NewLiquidationThreshold(
        LeToken leToken,
        uint256 oldLiquidationThresholdMantissa,
        uint256 newLiquidationThresholdMantissa
    );

    /// @notice Emitted when liquidation incentive is changed by admin
    event NewLiquidationIncentive(
        uint256 oldLiquidationIncentiveMantissa,
        uint256 newLiquidationIncentiveMantissa
    );

    /// @notice Emitted when price oracle is changed
    event NewPriceOracle(
        ResilientOracleInterface oldPriceOracle,
        ResilientOracleInterface newPriceOracle
    );

    /// @notice Emitted when an action is paused on a market
    event ActionPausedMarket(LeToken leToken, Action action, bool pauseState);

    /// @notice Emitted when borrow cap for a leToken is changed
    event NewBorrowCap(LeToken indexed leToken, uint256 newBorrowCap);

    /// @notice Emitted when the collateral threshold (in USD) for non-batch liquidations is changed
    event NewMinLiquidatableCollateral(
        uint256 oldMinLiquidatableCollateral,
        uint256 newMinLiquidatableCollateral
    );

    /// @notice Emitted when supply cap for a leToken is changed
    event NewSupplyCap(LeToken indexed leToken, uint256 newSupplyCap);

    /// @notice Emitted when a rewards distributor is added
    event NewRewardsDistributor(
        address indexed rewardsDistributor,
        address indexed rewardToken
    );

    /// @notice Emitted when a market is supported
    event MarketSupported(LeToken leToken);

    /// @notice Emitted when prime token contract address is changed
    event NewPrimeToken(IPrime oldPrimeToken, IPrime newPrimeToken);

    /// @notice Emitted when forced liquidation is enabled or disabled for a market
    event IsForcedLiquidationEnabledUpdated(
        address indexed leToken,
        bool enable
    );

    /// @notice Emitted when the borrowing or redeeming delegate rights are updated for an account
    event DelegateUpdated(
        address indexed approver,
        address indexed delegate,
        bool approved
    );

    /// @notice Thrown when collateral factor exceeds the upper bound
    error InvalidCollateralFactor();

    /// @notice Thrown when liquidation threshold exceeds the collateral factor
    error InvalidLiquidationThreshold();

    /// @notice Thrown when the action is only available to specific sender, but the real sender was different
    error UnexpectedSender(address expectedSender, address actualSender);

    /// @notice Thrown when the oracle returns an invalid price for some asset
    error PriceError(address leToken);

    /// @notice Thrown if LeToken unexpectedly returned a nonzero error code while trying to get account snapshot
    error SnapshotError(address leToken, address user);

    /// @notice Thrown when the market is not listed
    error MarketNotListed(address market);

    /// @notice Thrown when a market has an unexpected comptroller
    error ComptrollerMismatch();

    /// @notice Thrown when user is not member of market
    error MarketNotCollateral(address leToken, address user);

    /**
     * @notice Thrown during the liquidation if user's total collateral amount is lower than
     *   a predefined threshold. In this case only batch liquidations (either liquidateAccount
     *   or healAccount) are available.
     */
    error MinimalCollateralViolated(
        uint256 expectedGreaterThan,
        uint256 actual
    );
    error CollateralExceedsThreshold(
        uint256 expectedLessThanOrEqualTo,
        uint256 actual
    );
    error InsufficientCollateral(
        uint256 collateralToSeize,
        uint256 availableCollateral
    );

    /// @notice Thrown when the account doesn't have enough liquidity to redeem or borrow
    error InsufficientLiquidity();

    /// @notice Thrown when trying to liquidate a healthy account
    error InsufficientShortfall();

    /// @notice Thrown when trying to repay more than allowed by close factor
    error TooMuchRepay();

    /// @notice Thrown if the user is trying to exit a market in which they have an outstanding debt
    error NonzeroBorrowBalance();

    /// @notice Thrown when trying to perform an action that is paused
    error ActionPaused(address market, Action action);

    /// @notice Thrown when trying to add a market that is already listed
    error MarketAlreadyListed(address market);

    /// @notice Thrown if the supply cap is exceeded
    error SupplyCapExceeded(address market, uint256 cap);

    /// @notice Thrown if the borrow cap is exceeded
    error BorrowCapExceeded(address market, uint256 cap);

    /// @notice Thrown if delegate approval status is already set to the requested value
    error DelegationStatusUnchanged();

    /// @param poolRegistry_ Pool registry address
    /// @custom:oz-upgrades-unsafe-allow constructor
    /// @custom:error ZeroAddressNotAllowed is thrown when pool registry address is zero
    constructor(address poolRegistry_) {
        ensureNonzeroAddress(poolRegistry_);

        poolRegistry = poolRegistry_;
        _disableInitializers();
    }

    /**
     * @param loopLimit Limit for the loops can iterate to avoid the DOS
     * @param accessControlManager Access control manager contract address
     */
    function initialize(
        uint256 loopLimit,
        address accessControlManager
    ) external initializer {
        __Ownable2Step_init();
        __AccessControlled_init_unchained(accessControlManager);

        _setMaxLoopsLimit(loopLimit);
    }

    /**
     * @notice Add assets to be included in account liquidity calculation; enabling them to be used as collateral
     * @param leTokens The list of addresses of the leToken markets to be enabled
     * @return errors An array of NO_ERROR for compatibility with Kredly core tooling
     * @custom:event MarketEntered is emitted for each market on success
     * @custom:error ActionPaused error is thrown if entering any of the markets is paused
     * @custom:error MarketNotListed error is thrown if any of the markets is not listed
     * @custom:access Not restricted
     */
    function enterMarkets(
        address[] memory leTokens
    ) external override returns (uint256[] memory) {
        uint256 len = leTokens.length;

        uint256[] memory results = new uint256[](len);
        for (uint256 i; i < len; ++i) {
            LeToken leToken = LeToken(leTokens[i]);

            _addToMarket(leToken, msg.sender);
            results[i] = NO_ERROR;
        }

        return results;
    }

    /**
     * @notice Grants or revokes the borrowing or redeeming delegate rights to / from an account
     *  If allowed, the delegate will be able to borrow funds on behalf of the sender
     *  Upon a delegated borrow, the delegate will receive the funds, and the borrower
     *  will see the debt on their account
     *  Upon a delegated redeem, the delegate will receive the redeemed amount and the approver
     *  will see a deduction in his leToken balance
     * @param delegate The address to update the rights for
     * @param approved Whether to grant (true) or revoke (false) the borrowing or redeeming rights
     * @custom:event DelegateUpdated emits on success
     * @custom:error ZeroAddressNotAllowed is thrown when delegate address is zero
     * @custom:error DelegationStatusUnchanged is thrown if approval status is already set to the requested value
     * @custom:access Not restricted
     */
    function updateDelegate(address delegate, bool approved) external {
        ensureNonzeroAddress(delegate);
        if (approvedDelegates[msg.sender][delegate] == approved) {
            revert DelegationStatusUnchanged();
        }

        approvedDelegates[msg.sender][delegate] = approved;
        emit DelegateUpdated(msg.sender, delegate, approved);
    }

    /**
     * @notice Removes asset from sender's account liquidity calculation; disabling them as collateral
     * @dev Sender must not have an outstanding borrow balance in the asset,
     *  or be providing necessary collateral for an outstanding borrow.
     * @param leTokenAddress The address of the asset to be removed
     * @return error Always NO_ERROR for compatibility with Kredly core tooling
     * @custom:event MarketExited is emitted on success
     * @custom:error ActionPaused error is thrown if exiting the market is paused
     * @custom:error NonzeroBorrowBalance error is thrown if the user has an outstanding borrow in this market
     * @custom:error MarketNotListed error is thrown when the market is not listed
     * @custom:error InsufficientLiquidity error is thrown if exiting the market would lead to user's insolvency
     * @custom:error SnapshotError is thrown if some leToken fails to return the account's supply and borrows
     * @custom:error PriceError is thrown if the oracle returns an incorrect price for some asset
     * @custom:access Not restricted
     */
    function exitMarket(
        address leTokenAddress,
        bytes[] calldata priceUpdateData
    ) external override returns (uint256) {
        _checkActionPauseState(leTokenAddress, Action.EXIT_MARKET);
        LeToken leToken = LeToken(leTokenAddress);
        /* Get sender tokensHeld and amountOwed underlying from the leToken */
        (uint256 tokensHeld, uint256 amountOwed, ) = _safeGetAccountSnapshot(
            leToken,
            msg.sender
        );

        /* Fail if the sender has a borrow balance */
        if (amountOwed != 0) {
            revert NonzeroBorrowBalance();
        }

        /* Fail if the sender is not permitted to redeem all of their tokens */
        _checkRedeemAllowed(
            leTokenAddress,
            msg.sender,
            tokensHeld,
            priceUpdateData
        );

        Market storage marketToExit = markets[address(leToken)];

        /* Return true if the sender is not already ‘in’ the market */
        if (!marketToExit.accountMembership[msg.sender]) {
            return NO_ERROR;
        }

        /* Set leToken account membership to false */
        delete marketToExit.accountMembership[msg.sender];

        /* Delete leToken from the account’s list of assets */
        // load into memory for faster iteration
        LeToken[] memory userAssetList = accountAssets[msg.sender];
        uint256 len = userAssetList.length;

        uint256 assetIndex = len;
        for (uint256 i; i < len; ++i) {
            if (userAssetList[i] == leToken) {
                assetIndex = i;
                break;
            }
        }

        // We *must* have found the asset in the list or our redundant data structure is broken
        assert(assetIndex < len);

        // copy last item in list to location of item to be removed, reduce length by 1
        LeToken[] storage storedList = accountAssets[msg.sender];
        storedList[assetIndex] = storedList[storedList.length - 1];
        storedList.pop();

        emit MarketExited(leToken, msg.sender);

        return NO_ERROR;
    }

    /*** Policy Hooks ***/

    /**
     * @notice Checks if the account should be allowed to mint tokens in the given market
     * @param leToken The market to verify the mint against
     * @param minter The account which would get the minted tokens
     * @param mintAmount The amount of underlying being supplied to the market in exchange for tokens
     * @custom:error ActionPaused error is thrown if supplying to this market is paused
     * @custom:error MarketNotListed error is thrown when the market is not listed
     * @custom:error SupplyCapExceeded error is thrown if the total supply exceeds the cap after minting
     * @custom:access Not restricted
     */
    function preMintHook(
        address leToken,
        address minter,
        uint256 mintAmount
    ) external override {
        _checkActionPauseState(leToken, Action.MINT);

        if (!markets[leToken].isListed) {
            revert MarketNotListed(address(leToken));
        }

        uint256 supplyCap = supplyCaps[leToken];
        // Skipping the cap check for uncapped coins to save some gas
        if (supplyCap != type(uint256).max) {
            uint256 leTokenSupply = LeToken(leToken).totalSupply();
            Exp memory exchangeRate = Exp({
                mantissa: LeToken(leToken).exchangeRateStored()
            });
            uint256 nextTotalSupply = mul_ScalarTruncateAddUInt(
                exchangeRate,
                leTokenSupply,
                mintAmount
            );
            if (nextTotalSupply > supplyCap) {
                revert SupplyCapExceeded(leToken, supplyCap);
            }
        }

        // Keep the flywheel moving
        uint256 rewardDistributorsCount = rewardsDistributors.length;

        for (uint256 i; i < rewardDistributorsCount; ++i) {
            RewardsDistributor rewardsDistributor = rewardsDistributors[i];
            rewardsDistributor.updateRewardTokenSupplyIndex(leToken);
            rewardsDistributor.distributeSupplierRewardToken(leToken, minter);
        }
    }

    /**
     * @notice Validates mint, accrues interest and updates score in prime. Reverts on rejection. May emit logs.
     * @param leToken Asset being minted
     * @param minter The address minting the tokens
     * @param actualMintAmount The amount of the underlying asset being minted
     * @param mintTokens The number of tokens being minted
     */
    // solhint-disable-next-line no-unused-vars
    function mintVerify(
        address leToken,
        address minter,
        uint256 actualMintAmount,
        uint256 mintTokens
    ) external {
        if (address(prime) != address(0)) {
            prime.accrueInterestAndUpdateScore(minter, leToken);
        }
    }

    /**
     * @notice Checks if the account should be allowed to redeem tokens in the given market
     * @param leToken The market to verify the redeem against
     * @param redeemer The account which would redeem the tokens
     * @param redeemTokens The number of leTokens to exchange for the underlying asset in the market
     * @custom:error ActionPaused error is thrown if withdrawals are paused in this market
     * @custom:error MarketNotListed error is thrown when the market is not listed
     * @custom:error InsufficientLiquidity error is thrown if the withdrawal would lead to user's insolvency
     * @custom:error SnapshotError is thrown if some leToken fails to return the account's supply and borrows
     * @custom:error PriceError is thrown if the oracle returns an incorrect price for some asset
     * @custom:access Not restricted
     */
    function preRedeemHook(
        address leToken,
        address redeemer,
        uint256 redeemTokens,
        bytes[] calldata priceUpdateData
    ) external override {
        _checkActionPauseState(leToken, Action.REDEEM);

        _checkRedeemAllowed(leToken, redeemer, redeemTokens, priceUpdateData);

        // Keep the flywheel moving
        uint256 rewardDistributorsCount = rewardsDistributors.length;

        for (uint256 i; i < rewardDistributorsCount; ++i) {
            RewardsDistributor rewardsDistributor = rewardsDistributors[i];
            rewardsDistributor.updateRewardTokenSupplyIndex(leToken);
            rewardsDistributor.distributeSupplierRewardToken(leToken, redeemer);
        }
    }

    /**
     * @notice Validates redeem, accrues interest and updates score in prime. Reverts on rejection. May emit logs.
     * @param leToken Asset being redeemed
     * @param redeemer The address redeeming the tokens
     * @param redeemAmount The amount of the underlying asset being redeemed
     * @param redeemTokens The number of tokens being redeemed
     */
    function redeemVerify(
        address leToken,
        address redeemer,
        uint256 redeemAmount,
        uint256 redeemTokens
    ) external {
        if (address(prime) != address(0)) {
            prime.accrueInterestAndUpdateScore(redeemer, leToken);
        }
    }

    /**
     * @notice Validates repayBorrow, accrues interest and updates score in prime. Reverts on rejection. May emit logs.
     * @param leToken Asset being repaid
     * @param payer The address repaying the borrow
     * @param borrower The address of the borrower
     * @param actualRepayAmount The amount of underlying being repaid
     */
    function repayBorrowVerify(
        address leToken,
        address payer, // solhint-disable-line no-unused-vars
        address borrower,
        uint256 actualRepayAmount, // solhint-disable-line no-unused-vars
        uint256 borrowerIndex // solhint-disable-line no-unused-vars
    ) external {
        if (address(prime) != address(0)) {
            prime.accrueInterestAndUpdateScore(borrower, leToken);
        }
    }

    /**
     * @notice Validates liquidateBorrow, accrues interest and updates score in prime. Reverts on rejection. May emit logs.
     * @param leTokenBorrowed Asset which was borrowed by the borrower
     * @param leTokenCollateral Asset which was used as collateral and will be seized
     * @param liquidator The address repaying the borrow and seizing the collateral
     * @param borrower The address of the borrower
     * @param actualRepayAmount The amount of underlying being repaid
     * @param seizeTokens The amount of collateral token that will be seized
     */
    function liquidateBorrowVerify(
        address leTokenBorrowed,
        address leTokenCollateral, // solhint-disable-line no-unused-vars
        address liquidator,
        address borrower,
        uint256 actualRepayAmount, // solhint-disable-line no-unused-vars
        uint256 seizeTokens // solhint-disable-line no-unused-vars
    ) external {
        if (address(prime) != address(0)) {
            prime.accrueInterestAndUpdateScore(borrower, leTokenBorrowed);
            prime.accrueInterestAndUpdateScore(liquidator, leTokenBorrowed);
        }
    }

    /**
     * @notice Validates seize, accrues interest and updates score in prime. Reverts on rejection. May emit logs.
     * @param leTokenCollateral Asset which was used as collateral and will be seized
     * @param leTokenBorrowed Asset which was borrowed by the borrower
     * @param liquidator The address repaying the borrow and seizing the collateral
     * @param borrower The address of the borrower
     * @param seizeTokens The number of collateral tokens to seize
     */
    function seizeVerify(
        address leTokenCollateral,
        address leTokenBorrowed, // solhint-disable-line no-unused-vars
        address liquidator,
        address borrower,
        uint256 seizeTokens // solhint-disable-line no-unused-vars
    ) external {
        if (address(prime) != address(0)) {
            prime.accrueInterestAndUpdateScore(borrower, leTokenCollateral);
            prime.accrueInterestAndUpdateScore(liquidator, leTokenCollateral);
        }
    }

    /**
     * @notice Validates transfer, accrues interest and updates score in prime. Reverts on rejection. May emit logs.
     * @param leToken Asset being transferred
     * @param src The account which sources the tokens
     * @param dst The account which receives the tokens
     * @param transferTokens The number of leTokens to transfer
     */
    // solhint-disable-next-line no-unused-vars
    function transferVerify(
        address leToken,
        address src,
        address dst,
        uint256 transferTokens
    ) external {
        if (address(prime) != address(0)) {
            prime.accrueInterestAndUpdateScore(src, leToken);
            prime.accrueInterestAndUpdateScore(dst, leToken);
        }
    }

    /**
     * @notice Checks if the account should be allowed to borrow the underlying asset of the given market
     * @param leToken The market to verify the borrow against
     * @param borrower The account which would borrow the asset
     * @param borrowAmount The amount of underlying the account would borrow
     * @custom:error ActionPaused error is thrown if borrowing is paused in this market
     * @custom:error MarketNotListed error is thrown when the market is not listed
     * @custom:error InsufficientLiquidity error is thrown if there is not enough collateral to borrow
     * @custom:error BorrowCapExceeded is thrown if the borrow cap will be exceeded should this borrow succeed
     * @custom:error SnapshotError is thrown if some leToken fails to return the account's supply and borrows
     * @custom:error PriceError is thrown if the oracle returns an incorrect price for some asset
     * @custom:access Not restricted if leToken is enabled as collateral, otherwise only leToken
     */
    /// disable-eslint
    function preBorrowHook(
        address leToken,
        address borrower,
        uint256 borrowAmount,
        bytes[] calldata priceUpdateData
    ) external override {
        _checkActionPauseState(leToken, Action.BORROW);

        if (!markets[leToken].isListed) {
            revert MarketNotListed(address(leToken));
        }

        if (!markets[leToken].accountMembership[borrower]) {
            // only leTokens may call borrowAllowed if borrower not in market
            _checkSenderIs(leToken);

            // attempt to add borrower to the market or revert
            _addToMarket(LeToken(msg.sender), borrower);
        }

        // Update the prices of tokens
        updatePrices(borrower, priceUpdateData);

        if (oracle.getUnderlyingPrice(leToken) == 0) {
            revert PriceError(address(leToken));
        }

        uint256 borrowCap = borrowCaps[leToken];
        // Skipping the cap check for uncapped coins to save some gas
        if (borrowCap != type(uint256).max) {
            uint256 totalBorrows = LeToken(leToken).totalBorrows();
            uint256 badDebt = LeToken(leToken).badDebt();
            uint256 nextTotalBorrows = totalBorrows + borrowAmount + badDebt;
            if (nextTotalBorrows > borrowCap) {
                revert BorrowCapExceeded(leToken, borrowCap);
            }
        }

        AccountLiquiditySnapshot
            memory snapshot = _getHypotheticalLiquiditySnapshot(
                borrower,
                LeToken(leToken),
                0,
                borrowAmount,
                _getCollateralFactor
            );

        if (snapshot.shortfall > 0) {
            revert InsufficientLiquidity();
        }

        Exp memory borrowIndex = Exp({
            mantissa: LeToken(leToken).borrowIndex()
        });

        // Keep the flywheel moving
        uint256 rewardDistributorsCount = rewardsDistributors.length;

        for (uint256 i; i < rewardDistributorsCount; ++i) {
            RewardsDistributor rewardsDistributor = rewardsDistributors[i];
            rewardsDistributor.updateRewardTokenBorrowIndex(
                leToken,
                borrowIndex
            );
            rewardsDistributor.distributeBorrowerRewardToken(
                leToken,
                borrower,
                borrowIndex
            );
        }
    }

    /**
     * @notice Validates borrow, accrues interest and updates score in prime. Reverts on rejection. May emit logs.
     * @param leToken Asset whose underlying is being borrowed
     * @param borrower The address borrowing the underlying
     * @param borrowAmount The amount of the underlying asset requested to borrow
     */
    // solhint-disable-next-line no-unused-vars
    function borrowVerify(
        address leToken,
        address borrower,
        uint256 borrowAmount
    ) external {
        if (address(prime) != address(0)) {
            prime.accrueInterestAndUpdateScore(borrower, leToken);
        }
    }

    /**
     * @notice Checks if the account should be allowed to repay a borrow in the given market
     * @param leToken The market to verify the repay against
     * @param borrower The account which would borrowed the asset
     * @custom:error ActionPaused error is thrown if repayments are paused in this market
     * @custom:error MarketNotListed error is thrown when the market is not listed
     * @custom:access Not restricted
     */
    function preRepayHook(
        address leToken,
        address borrower,
        bytes[] calldata priceUpdateData
    ) external override {
        _checkActionPauseState(leToken, Action.REPAY);

        oracle.updatePrice(leToken, priceUpdateData);

        if (!markets[leToken].isListed) {
            revert MarketNotListed(address(leToken));
        }

        // Keep the flywheel moving
        uint256 rewardDistributorsCount = rewardsDistributors.length;

        for (uint256 i; i < rewardDistributorsCount; ++i) {
            Exp memory borrowIndex = Exp({
                mantissa: LeToken(leToken).borrowIndex()
            });
            RewardsDistributor rewardsDistributor = rewardsDistributors[i];
            rewardsDistributor.updateRewardTokenBorrowIndex(
                leToken,
                borrowIndex
            );
            rewardsDistributor.distributeBorrowerRewardToken(
                leToken,
                borrower,
                borrowIndex
            );
        }
    }

    /**
     * @notice Checks if the liquidation should be allowed to occur
     * @param leTokenBorrowed Asset which was borrowed by the borrower
     * @param leTokenCollateral Asset which was used as collateral and will be seized
     * @param borrower The address of the borrower
     * @param repayAmount The amount of underlying being repaid
     * @param skipLiquidityCheck Allows the borrow to be liquidated regardless of the account liquidity
     * @custom:error ActionPaused error is thrown if liquidations are paused in this market
     * @custom:error MarketNotListed error is thrown if either collateral or borrowed token is not listed
     * @custom:error TooMuchRepay error is thrown if the liquidator is trying to repay more than allowed by close factor
     * @custom:error MinimalCollateralViolated is thrown if the users' total collateral is lower than the threshold for non-batch liquidations
     * @custom:error InsufficientShortfall is thrown when trying to liquidate a healthy account
     * @custom:error SnapshotError is thrown if some leToken fails to return the account's supply and borrows
     * @custom:error PriceError is thrown if the oracle returns an incorrect price for some asset
     */
    function preLiquidateHook(
        address leTokenBorrowed,
        address leTokenCollateral,
        address borrower,
        uint256 repayAmount,
        bool skipLiquidityCheck,
        bytes[] calldata priceUpdateData
    ) external override {
        // Pause Action.LIQUIDATE on BORROWED TOKEN to prevent liquidating it.
        // If we want to pause liquidating to leTokenCollateral, we should pause
        // Action.SEIZE on it
        _checkActionPauseState(leTokenBorrowed, Action.LIQUIDATE);

        // Update the prices of tokens
        updatePrices(borrower, priceUpdateData);

        if (!markets[leTokenBorrowed].isListed) {
            revert MarketNotListed(address(leTokenBorrowed));
        }
        if (!markets[leTokenCollateral].isListed) {
            revert MarketNotListed(address(leTokenCollateral));
        }

        uint256 borrowBalance = LeToken(leTokenBorrowed).borrowBalanceStored(
            borrower
        );

        /* Allow accounts to be liquidated if it is a forced liquidation */
        if (skipLiquidityCheck || isForcedLiquidationEnabled[leTokenBorrowed]) {
            if (repayAmount > borrowBalance) {
                revert TooMuchRepay();
            }
            return;
        }

        /* The borrower must have shortfall and collateral > threshold in order to be liquidatable */
        AccountLiquiditySnapshot memory snapshot = _getCurrentLiquiditySnapshot(
            borrower,
            _getLiquidationThreshold
        );

        if (snapshot.totalCollateral <= minLiquidatableCollateral) {
            /* The liquidator should use either liquidateAccount or healAccount */
            revert MinimalCollateralViolated(
                minLiquidatableCollateral,
                snapshot.totalCollateral
            );
        }

        if (snapshot.shortfall == 0) {
            revert InsufficientShortfall();
        }

        /* The liquidator may not repay more than what is allowed by the closeFactor */
        uint256 maxClose = mul_ScalarTruncate(
            Exp({mantissa: closeFactorMantissa}),
            borrowBalance
        );
        if (repayAmount > maxClose) {
            revert TooMuchRepay();
        }
    }

    /**
     * @notice Checks if the seizing of assets should be allowed to occur
     * @param leTokenCollateral Asset which was used as collateral and will be seized
     * @param seizerContract Contract that tries to seize the asset (either borrowed leToken or Comptroller)
     * @param liquidator The address repaying the borrow and seizing the collateral
     * @param borrower The address of the borrower
     * @custom:error ActionPaused error is thrown if seizing this type of collateral is paused
     * @custom:error MarketNotListed error is thrown if either collateral or borrowed token is not listed
     * @custom:error ComptrollerMismatch error is when seizer contract or seized asset belong to different pools
     * @custom:access Not restricted
     */
    function preSeizeHook(
        address leTokenCollateral,
        address seizerContract,
        address liquidator,
        address borrower
    ) external override {
        // Pause Action.SEIZE on COLLATERAL to prevent seizing it.
        // If we want to pause liquidating leTokenBorrowed, we should pause
        // Action.LIQUIDATE on it
        _checkActionPauseState(leTokenCollateral, Action.SEIZE);

        Market storage market = markets[leTokenCollateral];

        if (!market.isListed) {
            revert MarketNotListed(leTokenCollateral);
        }

        if (seizerContract == address(this)) {
            // If Comptroller is the seizer, just check if collateral's comptroller
            // is equal to the current address
            if (
                address(LeToken(leTokenCollateral).comptroller()) !=
                address(this)
            ) {
                revert ComptrollerMismatch();
            }
        } else {
            // If the seizer is not the Comptroller, check that the seizer is a
            // listed market, and that the markets' comptrollers match
            if (!markets[seizerContract].isListed) {
                revert MarketNotListed(seizerContract);
            }
            if (
                LeToken(leTokenCollateral).comptroller() !=
                LeToken(seizerContract).comptroller()
            ) {
                revert ComptrollerMismatch();
            }
        }

        if (!market.accountMembership[borrower]) {
            revert MarketNotCollateral(leTokenCollateral, borrower);
        }

        // Keep the flywheel moving
        uint256 rewardDistributorsCount = rewardsDistributors.length;

        for (uint256 i; i < rewardDistributorsCount; ++i) {
            RewardsDistributor rewardsDistributor = rewardsDistributors[i];
            rewardsDistributor.updateRewardTokenSupplyIndex(leTokenCollateral);
            rewardsDistributor.distributeSupplierRewardToken(
                leTokenCollateral,
                borrower
            );
            rewardsDistributor.distributeSupplierRewardToken(
                leTokenCollateral,
                liquidator
            );
        }
    }

    /**
     * @notice Checks if the account should be allowed to transfer tokens in the given market
     * @param leToken The market to verify the transfer against
     * @param src The account which sources the tokens
     * @param dst The account which receives the tokens
     * @param transferTokens The number of leTokens to transfer
     * @custom:error ActionPaused error is thrown if withdrawals are paused in this market
     * @custom:error MarketNotListed error is thrown when the market is not listed
     * @custom:error InsufficientLiquidity error is thrown if the withdrawal would lead to user's insolvency
     * @custom:error SnapshotError is thrown if some leToken fails to return the account's supply and borrows
     * @custom:error PriceError is thrown if the oracle returns an incorrect price for some asset
     * @custom:access Not restricted
     */
    function preTransferHook(
        address leToken,
        address src,
        address dst,
        uint256 transferTokens
    ) external override {
        _checkActionPauseState(leToken, Action.TRANSFER);

        // Currently the only consideration is whether or not
        //  the src is allowed to redeem this many tokens

        // Keep the flywheel moving
        uint256 rewardDistributorsCount = rewardsDistributors.length;

        for (uint256 i; i < rewardDistributorsCount; ++i) {
            RewardsDistributor rewardsDistributor = rewardsDistributors[i];
            rewardsDistributor.updateRewardTokenSupplyIndex(leToken);
            rewardsDistributor.distributeSupplierRewardToken(leToken, src);
            rewardsDistributor.distributeSupplierRewardToken(leToken, dst);
        }
    }

    /*** Pool-level operations ***/

    /**
     * @notice Seizes all the remaining collateral, makes msg.sender repay the existing
     *   borrows, and treats the rest of the debt as bad debt (for each market).
     *   The sender has to repay a certain percentage of the debt, computed as
     *   collateral / (borrows * liquidationIncentive).
     * @param user account to heal
     * @custom:error CollateralExceedsThreshold error is thrown when the collateral is too big for healing
     * @custom:error SnapshotError is thrown if some leToken fails to return the account's supply and borrows
     * @custom:error PriceError is thrown if the oracle returns an incorrect price for some asset
     * @custom:access Not restricted
     */
    function healAccount(address user) external {
        LeToken[] memory userAssets = accountAssets[user];
        uint256 userAssetsCount = userAssets.length;

        {
            ResilientOracleInterface oracle_ = oracle;
            // We need all user's markets to be fresh for the computations to be correct
            for (uint256 i; i < userAssetsCount; ++i) {
                userAssets[i].accrueInterest();
            }
        }

        AccountLiquiditySnapshot memory snapshot = _getCurrentLiquiditySnapshot(
            user,
            _getLiquidationThreshold
        );

        if (snapshot.totalCollateral > minLiquidatableCollateral) {
            revert CollateralExceedsThreshold(
                minLiquidatableCollateral,
                snapshot.totalCollateral
            );
        }

        if (snapshot.shortfall == 0) {
            revert InsufficientShortfall();
        }

        // percentage = collateral / (borrows * liquidation incentive)
        Exp memory collateral = Exp({mantissa: snapshot.totalCollateral});
        Exp memory scaledBorrows = mul_(
            Exp({mantissa: snapshot.borrows}),
            Exp({mantissa: liquidationIncentiveMantissa})
        );

        Exp memory percentage = div_(collateral, scaledBorrows);
        if (lessThanExp(Exp({mantissa: MANTISSA_ONE}), percentage)) {
            revert CollateralExceedsThreshold(
                scaledBorrows.mantissa,
                collateral.mantissa
            );
        }

        for (uint256 i; i < userAssetsCount; ++i) {
            LeToken market = userAssets[i];

            (uint256 tokens, uint256 borrowBalance, ) = _safeGetAccountSnapshot(
                market,
                user
            );
            uint256 repaymentAmount = mul_ScalarTruncate(
                percentage,
                borrowBalance
            );

            // Seize the entire collateral
            if (tokens != 0) {
                market.seize(msg.sender, user, tokens);
            }
            // Repay a certain percentage of the borrow, forgive the rest
            if (borrowBalance != 0) {
                bytes[] memory priceUpdateData = new bytes[](0);
                market.healBorrow(
                    msg.sender,
                    user,
                    repaymentAmount,
                    priceUpdateData
                );
            }
        }
    }

    /**
     * @notice Liquidates all borrows of the borrower. Callable only if the collateral is less than
     *   a predefined threshold, and the account collateral can be seized to cover all borrows. If
     *   the collateral is higher than the threshold, use regular liquidations. If the collateral is
     *   below the threshold, and the account is insolvent, use healAccount.
     * @param borrower the borrower address
     * @param orders an array of liquidation orders
     * @custom:error CollateralExceedsThreshold error is thrown when the collateral is too big for a batch liquidation
     * @custom:error InsufficientCollateral error is thrown when there is not enough collateral to cover the debt
     * @custom:error SnapshotError is thrown if some leToken fails to return the account's supply and borrows
     * @custom:error PriceError is thrown if the oracle returns an incorrect price for some asset
     * @custom:access Not restricted
     */
    function liquidateAccount(
        address borrower,
        LiquidationOrder[] calldata orders,
        bytes[] memory priceUpdateData
    ) external {
        // We will accrue interest and update the oracle prices later during the liquidation

        AccountLiquiditySnapshot memory snapshot = _getCurrentLiquiditySnapshot(
            borrower,
            _getLiquidationThreshold
        );

        if (snapshot.totalCollateral > minLiquidatableCollateral) {
            // You should use the regular leToken.liquidateBorrow(...) call
            revert CollateralExceedsThreshold(
                minLiquidatableCollateral,
                snapshot.totalCollateral
            );
        }

        uint256 collateralToSeize = mul_ScalarTruncate(
            Exp({mantissa: liquidationIncentiveMantissa}),
            snapshot.borrows
        );
        if (collateralToSeize >= snapshot.totalCollateral) {
            // There is not enough collateral to seize. Use healBorrow to repay some part of the borrow
            // and record bad debt.
            revert InsufficientCollateral(
                collateralToSeize,
                snapshot.totalCollateral
            );
        }

        if (snapshot.shortfall == 0) {
            revert InsufficientShortfall();
        }

        uint256 ordersCount = orders.length;

        _ensureMaxLoops(ordersCount / 2);

        for (uint256 i; i < ordersCount; ++i) {
            if (!markets[address(orders[i].leTokenBorrowed)].isListed) {
                revert MarketNotListed(address(orders[i].leTokenBorrowed));
            }
            if (!markets[address(orders[i].leTokenCollateral)].isListed) {
                revert MarketNotListed(address(orders[i].leTokenCollateral));
            }

            LiquidationOrder calldata order = orders[i];
            order.leTokenBorrowed.forceLiquidateBorrow(
                msg.sender,
                borrower,
                order.repayAmount,
                order.leTokenCollateral,
                true,
                priceUpdateData
            );
        }

        LeToken[] memory borrowMarkets = accountAssets[borrower];
        uint256 marketsCount = borrowMarkets.length;

        for (uint256 i; i < marketsCount; ++i) {
            (, uint256 borrowBalance, ) = _safeGetAccountSnapshot(
                borrowMarkets[i],
                borrower
            );
            require(
                borrowBalance == 0,
                "Nonzero borrow balance after liquidation"
            );
        }
    }

    /**
     * @notice Sets the closeFactor to use when liquidating borrows
     * @param newCloseFactorMantissa New close factor, scaled by 1e18
     * @custom:event Emits NewCloseFactor on success
     * @custom:access Controlled by AccessControlManager
     */
    function setCloseFactor(uint256 newCloseFactorMantissa) external {
        _checkAccessAllowed("setCloseFactor(uint256)");
        require(
            MAX_CLOSE_FACTOR_MANTISSA >= newCloseFactorMantissa,
            "Close factor greater than maximum close factor"
        );
        require(
            MIN_CLOSE_FACTOR_MANTISSA <= newCloseFactorMantissa,
            "Close factor smaller than minimum close factor"
        );

        uint256 oldCloseFactorMantissa = closeFactorMantissa;
        closeFactorMantissa = newCloseFactorMantissa;
        emit NewCloseFactor(oldCloseFactorMantissa, newCloseFactorMantissa);
    }

    /**
     * @notice Sets the collateralFactor for a market
     * @dev This function is restricted by the AccessControlManager
     * @param leToken The market to set the factor on
     * @param newCollateralFactorMantissa The new collateral factor, scaled by 1e18
     * @param newLiquidationThresholdMantissa The new liquidation threshold, scaled by 1e18
     * @custom:event Emits NewCollateralFactor when collateral factor is updated
     *    and NewLiquidationThreshold when liquidation threshold is updated
     * @custom:error MarketNotListed error is thrown when the market is not listed
     * @custom:error InvalidCollateralFactor error is thrown when collateral factor is too high
     * @custom:error InvalidLiquidationThreshold error is thrown when liquidation threshold is lower than collateral factor
     * @custom:error PriceError is thrown when the oracle returns an invalid price for the asset
     * @custom:access Controlled by AccessControlManager
     */
    function setCollateralFactor(
        LeToken leToken,
        uint256 newCollateralFactorMantissa,
        uint256 newLiquidationThresholdMantissa
    ) external {
        _checkAccessAllowed("setCollateralFactor(address,uint256,uint256)");

        // Verify market is listed
        Market storage market = markets[address(leToken)];
        if (!market.isListed) {
            revert MarketNotListed(address(leToken));
        }

        // Check collateral factor <= 0.9
        if (newCollateralFactorMantissa > MAX_COLLATERAL_FACTOR_MANTISSA) {
            revert InvalidCollateralFactor();
        }

        // Ensure that liquidation threshold <= 1
        if (newLiquidationThresholdMantissa > MANTISSA_ONE) {
            revert InvalidLiquidationThreshold();
        }

        // Ensure that liquidation threshold >= CF
        if (newLiquidationThresholdMantissa < newCollateralFactorMantissa) {
            revert InvalidLiquidationThreshold();
        }

        // If collateral factor != 0, fail if price == 0
        if (
            newCollateralFactorMantissa != 0 &&
            oracle.getUnderlyingPrice(address(leToken)) == 0
        ) {
            revert PriceError(address(leToken));
        }

        uint256 oldCollateralFactorMantissa = market.collateralFactorMantissa;
        if (newCollateralFactorMantissa != oldCollateralFactorMantissa) {
            market.collateralFactorMantissa = newCollateralFactorMantissa;
            emit NewCollateralFactor(
                leToken,
                oldCollateralFactorMantissa,
                newCollateralFactorMantissa
            );
        }

        uint256 oldLiquidationThresholdMantissa = market
            .liquidationThresholdMantissa;
        if (
            newLiquidationThresholdMantissa != oldLiquidationThresholdMantissa
        ) {
            market
                .liquidationThresholdMantissa = newLiquidationThresholdMantissa;
            emit NewLiquidationThreshold(
                leToken,
                oldLiquidationThresholdMantissa,
                newLiquidationThresholdMantissa
            );
        }
    }

    /**
     * @notice Sets liquidationIncentive
     * @dev This function is restricted by the AccessControlManager
     * @param newLiquidationIncentiveMantissa New liquidationIncentive scaled by 1e18
     * @custom:event Emits NewLiquidationIncentive on success
     * @custom:access Controlled by AccessControlManager
     */
    function setLiquidationIncentive(
        uint256 newLiquidationIncentiveMantissa
    ) external {
        require(
            newLiquidationIncentiveMantissa >= MANTISSA_ONE,
            "liquidation incentive should be greater than 1e18"
        );

        _checkAccessAllowed("setLiquidationIncentive(uint256)");

        // Save current value for use in log
        uint256 oldLiquidationIncentiveMantissa = liquidationIncentiveMantissa;

        // Set liquidation incentive to new incentive
        liquidationIncentiveMantissa = newLiquidationIncentiveMantissa;

        // Emit event with old incentive, new incentive
        emit NewLiquidationIncentive(
            oldLiquidationIncentiveMantissa,
            newLiquidationIncentiveMantissa
        );
    }

    /**
     * @notice Add the market to the markets mapping and set it as listed
     * @dev Only callable by the PoolRegistry
     * @param leToken The address of the market (token) to list
     * @custom:error MarketAlreadyListed is thrown if the market is already listed in this pool
     * @custom:access Only PoolRegistry
     */
    function supportMarket(LeToken leToken) external {
        _checkSenderIs(poolRegistry);

        if (markets[address(leToken)].isListed) {
            revert MarketAlreadyListed(address(leToken));
        }

        require(leToken.isLeToken(), "Comptroller: Invalid leToken"); // Sanity check to make sure its really a LeToken

        Market storage newMarket = markets[address(leToken)];
        newMarket.isListed = true;
        newMarket.collateralFactorMantissa = 0;
        newMarket.liquidationThresholdMantissa = 0;

        _addMarket(address(leToken));

        uint256 rewardDistributorsCount = rewardsDistributors.length;

        for (uint256 i; i < rewardDistributorsCount; ++i) {
            rewardsDistributors[i].initializeMarket(address(leToken));
        }

        emit MarketSupported(leToken);
    }

    /**
     * @notice Set the given borrow caps for the given leToken markets. Borrowing that brings total borrows to or above borrow cap will revert.
     * @dev This function is restricted by the AccessControlManager
     * @dev A borrow cap of type(uint256).max corresponds to unlimited borrowing.
     * @dev Borrow caps smaller than the current total borrows are accepted. This way, new borrows will not be allowed
            until the total borrows amount goes below the new borrow cap
     * @param leTokens The addresses of the markets (tokens) to change the borrow caps for
     * @param newBorrowCaps The new borrow cap values in underlying to be set. A value of type(uint256).max corresponds to unlimited borrowing.
     * @custom:access Controlled by AccessControlManager
     */
    function setMarketBorrowCaps(
        LeToken[] calldata leTokens,
        uint256[] calldata newBorrowCaps
    ) external {
        _checkAccessAllowed("setMarketBorrowCaps(address[],uint256[])");

        uint256 numMarkets = leTokens.length;
        uint256 numBorrowCaps = newBorrowCaps.length;

        require(
            numMarkets != 0 && numMarkets == numBorrowCaps,
            "invalid input"
        );

        _ensureMaxLoops(numMarkets);

        for (uint256 i; i < numMarkets; ++i) {
            borrowCaps[address(leTokens[i])] = newBorrowCaps[i];
            emit NewBorrowCap(leTokens[i], newBorrowCaps[i]);
        }
    }

    /**
     * @notice Set the given supply caps for the given leToken markets. Supply that brings total Supply to or above supply cap will revert.
     * @dev This function is restricted by the AccessControlManager
     * @dev A supply cap of type(uint256).max corresponds to unlimited supply.
     * @dev Supply caps smaller than the current total supplies are accepted. This way, new supplies will not be allowed
            until the total supplies amount goes below the new supply cap
     * @param leTokens The addresses of the markets (tokens) to change the supply caps for
     * @param newSupplyCaps The new supply cap values in underlying to be set. A value of type(uint256).max corresponds to unlimited supply.
     * @custom:access Controlled by AccessControlManager
     */
    function setMarketSupplyCaps(
        LeToken[] calldata leTokens,
        uint256[] calldata newSupplyCaps
    ) external {
        _checkAccessAllowed("setMarketSupplyCaps(address[],uint256[])");
        uint256 leTokensCount = leTokens.length;

        require(leTokensCount != 0, "invalid number of markets");
        require(
            leTokensCount == newSupplyCaps.length,
            "invalid number of markets"
        );

        _ensureMaxLoops(leTokensCount);

        for (uint256 i; i < leTokensCount; ++i) {
            supplyCaps[address(leTokens[i])] = newSupplyCaps[i];
            emit NewSupplyCap(leTokens[i], newSupplyCaps[i]);
        }
    }

    /**
     * @notice Pause/unpause specified actions
     * @dev This function is restricted by the AccessControlManager
     * @param marketsList Markets to pause/unpause the actions on
     * @param actionsList List of action ids to pause/unpause
     * @param paused The new paused state (true=paused, false=unpaused)
     * @custom:access Controlled by AccessControlManager
     */
    function setActionsPaused(
        LeToken[] calldata marketsList,
        Action[] calldata actionsList,
        bool paused
    ) external {
        _checkAccessAllowed("setActionsPaused(address[],uint256[],bool)");

        uint256 marketsCount = marketsList.length;
        uint256 actionsCount = actionsList.length;

        _ensureMaxLoops(marketsCount * actionsCount);

        for (uint256 marketIdx; marketIdx < marketsCount; ++marketIdx) {
            for (uint256 actionIdx; actionIdx < actionsCount; ++actionIdx) {
                _setActionPaused(
                    address(marketsList[marketIdx]),
                    actionsList[actionIdx],
                    paused
                );
            }
        }
    }

    /**
     * @notice Set the given collateral threshold for non-batch liquidations. Regular liquidations
     *   will fail if the collateral amount is less than this threshold. Liquidators should use batch
     *   operations like liquidateAccount or healAccount.
     * @dev This function is restricted by the AccessControlManager
     * @param newMinLiquidatableCollateral The new min liquidatable collateral (in USD).
     * @custom:access Controlled by AccessControlManager
     */
    function setMinLiquidatableCollateral(
        uint256 newMinLiquidatableCollateral
    ) external {
        _checkAccessAllowed("setMinLiquidatableCollateral(uint256)");

        uint256 oldMinLiquidatableCollateral = minLiquidatableCollateral;
        minLiquidatableCollateral = newMinLiquidatableCollateral;
        emit NewMinLiquidatableCollateral(
            oldMinLiquidatableCollateral,
            newMinLiquidatableCollateral
        );
    }

    /**
     * @notice Add a new RewardsDistributor and initialize it with all markets. We can add several RewardsDistributor
     * contracts with the same rewardToken, and there could be overlaping among them considering the last reward block
     * @dev Only callable by the admin
     * @param _rewardsDistributor Address of the RewardDistributor contract to add
     * @custom:access Only Governance
     * @custom:event Emits NewRewardsDistributor with distributor address
     */
    function addRewardsDistributor(
        RewardsDistributor _rewardsDistributor
    ) external onlyOwner {
        require(
            !rewardsDistributorExists[address(_rewardsDistributor)],
            "already exists"
        );

        uint256 rewardsDistributorsLen = rewardsDistributors.length;
        _ensureMaxLoops(rewardsDistributorsLen + 1);

        rewardsDistributors.push(_rewardsDistributor);
        rewardsDistributorExists[address(_rewardsDistributor)] = true;

        uint256 marketsCount = allMarkets.length;

        for (uint256 i; i < marketsCount; ++i) {
            _rewardsDistributor.initializeMarket(address(allMarkets[i]));
        }

        emit NewRewardsDistributor(
            address(_rewardsDistributor),
            address(_rewardsDistributor.rewardToken())
        );
    }

    /**
     * @notice Sets a new price oracle for the Comptroller
     * @dev Only callable by the admin
     * @param newOracle Address of the new price oracle to set
     * @custom:event Emits NewPriceOracle on success
     * @custom:error ZeroAddressNotAllowed is thrown when the new oracle address is zero
     */
    function setPriceOracle(
        ResilientOracleInterface newOracle
    ) external onlyOwner {
        ensureNonzeroAddress(address(newOracle));

        ResilientOracleInterface oldOracle = oracle;
        oracle = newOracle;
        emit NewPriceOracle(oldOracle, newOracle);
    }

    /**
     * @notice Set the for loop iteration limit to avoid DOS
     * @param limit Limit for the max loops can execute at a time
     */
    function setMaxLoopsLimit(uint256 limit) external onlyOwner {
        _setMaxLoopsLimit(limit);
    }

    /**
     * @notice Sets the prime token contract for the comptroller
     * @param _prime Address of the Prime contract
     */
    function setPrimeToken(IPrime _prime) external onlyOwner {
        ensureNonzeroAddress(address(_prime));

        emit NewPrimeToken(prime, _prime);
        prime = _prime;
    }

    /**
     * @notice Enables forced liquidations for a market. If forced liquidation is enabled,
     * borrows in the market may be liquidated regardless of the account liquidity
     * @param leTokenBorrowed Borrowed leToken
     * @param enable Whether to enable forced liquidations
     */
    function setForcedLiquidation(
        address leTokenBorrowed,
        bool enable
    ) external {
        _checkAccessAllowed("setForcedLiquidation(address,bool)");
        ensureNonzeroAddress(leTokenBorrowed);

        if (!markets[leTokenBorrowed].isListed) {
            revert MarketNotListed(leTokenBorrowed);
        }

        isForcedLiquidationEnabled[leTokenBorrowed] = enable;
        emit IsForcedLiquidationEnabledUpdated(leTokenBorrowed, enable);
    }

    /**
     * @notice Determine the current account liquidity with respect to liquidation threshold requirements
     * @dev The interface of this function is intentionally kept compatible with Compound and Kredly Core
     * @param account The account get liquidity for
     * @return error Always NO_ERROR for compatibility with Kredly core tooling
     * @return liquidity Account liquidity in excess of liquidation threshold requirements,
     * @return shortfall Account shortfall below liquidation threshold requirements
     */
    function getAccountLiquidity(
        address account
    )
        external
        view
        returns (uint256 error, uint256 liquidity, uint256 shortfall)
    {
        AccountLiquiditySnapshot memory snapshot = _getCurrentLiquiditySnapshot(
            account,
            _getLiquidationThreshold
        );
        return (NO_ERROR, snapshot.liquidity, snapshot.shortfall);
    }

    /**
     * @notice Determine the current account liquidity with respect to collateral requirements
     * @dev The interface of this function is intentionally kept compatible with Compound and Kredly Core
     * @param account The account get liquidity for
     * @return error Always NO_ERROR for compatibility with Kredly core tooling
     * @return liquidity Account liquidity in excess of collateral requirements,
     * @return shortfall Account shortfall below collateral requirements
     */
    function getBorrowingPower(
        address account
    )
        external
        view
        returns (uint256 error, uint256 liquidity, uint256 shortfall)
    {
        AccountLiquiditySnapshot memory snapshot = _getCurrentLiquiditySnapshot(
            account,
            _getCollateralFactor
        );
        return (NO_ERROR, snapshot.liquidity, snapshot.shortfall);
    }

    /**
     * @notice Determine what the account liquidity would be if the given amounts were redeemed/borrowed
     * @dev The interface of this function is intentionally kept compatible with Compound and Kredly Core
     * @param leTokenModify The market to hypothetically redeem/borrow in
     * @param account The account to determine liquidity for
     * @param redeemTokens The number of tokens to hypothetically redeem
     * @param borrowAmount The amount of underlying to hypothetically borrow
     * @return error Always NO_ERROR for compatibility with Kredly core tooling
     * @return liquidity Hypothetical account liquidity in excess of collateral requirements,
     * @return shortfall Hypothetical account shortfall below collateral requirements
     */
    function getHypotheticalAccountLiquidity(
        address account,
        address leTokenModify,
        uint256 redeemTokens,
        uint256 borrowAmount
    )
        external
        view
        returns (uint256 error, uint256 liquidity, uint256 shortfall)
    {
        AccountLiquiditySnapshot
            memory snapshot = _getHypotheticalLiquiditySnapshot(
                account,
                LeToken(leTokenModify),
                redeemTokens,
                borrowAmount,
                _getCollateralFactor
            );
        return (NO_ERROR, snapshot.liquidity, snapshot.shortfall);
    }

    /**
     * @notice Return all of the markets
     * @dev The automatic getter may be used to access an individual market.
     * @return markets The list of market addresses
     */
    function getAllMarkets() external view override returns (LeToken[] memory) {
        return allMarkets;
    }

    /**
     * @notice Check if a market is marked as listed (active)
     * @param leToken leToken Address for the market to check
     * @return listed True if listed otherwise false
     */
    function isMarketListed(LeToken leToken) external view returns (bool) {
        return markets[address(leToken)].isListed;
    }

    /*** Assets You Are In ***/

    /**
     * @notice Returns the assets an account has entered
     * @param account The address of the account to pull assets for
     * @return A list with the assets the account has entered
     */
    function getAssetsIn(
        address account
    ) external view returns (LeToken[] memory) {
        LeToken[] memory assetsIn = accountAssets[account];

        return assetsIn;
    }

    /**
     * @notice Returns whether the given account is entered in a given market
     * @param account The address of the account to check
     * @param leToken The leToken to check
     * @return True if the account is in the market specified, otherwise false.
     */
    function checkMembership(
        address account,
        LeToken leToken
    ) external view returns (bool) {
        return markets[address(leToken)].accountMembership[account];
    }

    /**
     * @notice Calculate number of tokens of collateral asset to seize given an underlying amount
     * @dev Used in liquidation (called in leToken.liquidateBorrowFresh)
     * @param leTokenBorrowed The address of the borrowed leToken
     * @param leTokenCollateral The address of the collateral leToken
     * @param actualRepayAmount The amount of leTokenBorrowed underlying to convert into leTokenCollateral tokens
     * @return error Always NO_ERROR for compatibility with Kredly core tooling
     * @return tokensToSeize Number of leTokenCollateral tokens to be seized in a liquidation
     * @custom:error PriceError if the oracle returns an invalid price
     */
    function liquidateCalculateSeizeTokens(
        address leTokenBorrowed,
        address leTokenCollateral,
        uint256 actualRepayAmount
    ) external view override returns (uint256 error, uint256 tokensToSeize) {
        /* Read oracle prices for borrowed and collateral markets */
        uint256 priceBorrowedMantissa = _safeGetUnderlyingPrice(
            LeToken(leTokenBorrowed)
        );
        uint256 priceCollateralMantissa = _safeGetUnderlyingPrice(
            LeToken(leTokenCollateral)
        );

        /*
         * Get the exchange rate and calculate the number of collateral tokens to seize:
         *  seizeAmount = actualRepayAmount * liquidationIncentive * priceBorrowed / priceCollateral
         *  seizeTokens = seizeAmount / exchangeRate
         *   = actualRepayAmount * (liquidationIncentive * priceBorrowed) / (priceCollateral * exchangeRate)
         */
        uint256 exchangeRateMantissa = LeToken(leTokenCollateral)
            .exchangeRateStored(); // Note: reverts on error
        uint256 seizeTokens;
        Exp memory numerator;
        Exp memory denominator;
        Exp memory ratio;

        numerator = mul_(
            Exp({mantissa: liquidationIncentiveMantissa}),
            Exp({mantissa: priceBorrowedMantissa})
        );
        denominator = mul_(
            Exp({mantissa: priceCollateralMantissa}),
            Exp({mantissa: exchangeRateMantissa})
        );
        ratio = div_(numerator, denominator);

        seizeTokens = mul_ScalarTruncate(ratio, actualRepayAmount);

        return (NO_ERROR, seizeTokens);
    }

    /**
     * @notice Returns reward speed given a leToken
     * @param leToken The leToken to get the reward speeds for
     * @return rewardSpeeds Array of total supply and borrow speeds and reward token for all reward distributors
     */
    function getRewardsByMarket(
        address leToken
    ) external view returns (RewardSpeeds[] memory rewardSpeeds) {
        uint256 rewardsDistributorsLength = rewardsDistributors.length;
        rewardSpeeds = new RewardSpeeds[](rewardsDistributorsLength);
        for (uint256 i; i < rewardsDistributorsLength; ++i) {
            RewardsDistributor rewardsDistributor = rewardsDistributors[i];
            address rewardToken = address(rewardsDistributor.rewardToken());
            rewardSpeeds[i] = RewardSpeeds({
                rewardToken: rewardToken,
                supplySpeed: rewardsDistributor.rewardTokenSupplySpeeds(
                    leToken
                ),
                borrowSpeed: rewardsDistributor.rewardTokenBorrowSpeeds(leToken)
            });
        }
        return rewardSpeeds;
    }

    /**
     * @notice Return all reward distributors for this pool
     * @return Array of RewardDistributor addresses
     */
    function getRewardDistributors()
        external
        view
        returns (RewardsDistributor[] memory)
    {
        return rewardsDistributors;
    }

    /**
     * @notice A marker method that returns true for a valid Comptroller contract
     * @return Always true
     */
    function isComptroller() external pure override returns (bool) {
        return true;
    }

    /**
     * @notice Update the prices of all the tokens associated with the provided account
     * @param account Address of the account to get associated tokens with
     */
    function updatePrices(
        address account,
        bytes[] calldata priceUpdateData
    ) public {
        LeToken[] memory leTokens = accountAssets[account];
        uint256 leTokensCount = leTokens.length;

        ResilientOracleInterface oracle_ = oracle;

        for (uint256 i; i < leTokensCount; ++i) {
            oracle_.updatePrice(address(leTokens[i]), priceUpdateData);
        }
    }

    /**
     * @notice Checks if a certain action is paused on a market
     * @param market leToken address
     * @param action Action to check
     * @return paused True if the action is paused otherwise false
     */
    function actionPaused(
        address market,
        Action action
    ) public view returns (bool) {
        return _actionPaused[market][action];
    }

    /**
     * @notice Add the market to the borrower's "assets in" for liquidity calculations
     * @param leToken The market to enter
     * @param borrower The address of the account to modify
     */
    function _addToMarket(LeToken leToken, address borrower) internal {
        _checkActionPauseState(address(leToken), Action.ENTER_MARKET);
        Market storage marketToJoin = markets[address(leToken)];

        if (!marketToJoin.isListed) {
            revert MarketNotListed(address(leToken));
        }

        if (marketToJoin.accountMembership[borrower]) {
            // already joined
            return;
        }

        // survived the gauntlet, add to list
        // NOTE: we store these somewhat redundantly as a significant optimization
        //  this avoids having to iterate through the list for the most common use cases
        //  that is, only when we need to perform liquidity checks
        //  and not whenever we want to check if an account is in a particular market
        marketToJoin.accountMembership[borrower] = true;
        accountAssets[borrower].push(leToken);

        emit MarketEntered(leToken, borrower);
    }

    /**
     * @notice Internal function to validate that a market hasn't already been added
     * and if it hasn't adds it
     * @param leToken The market to support
     */
    function _addMarket(address leToken) internal {
        uint256 marketsCount = allMarkets.length;

        for (uint256 i; i < marketsCount; ++i) {
            if (allMarkets[i] == LeToken(leToken)) {
                revert MarketAlreadyListed(leToken);
            }
        }
        allMarkets.push(LeToken(leToken));
        marketsCount = allMarkets.length;
        _ensureMaxLoops(marketsCount);
    }

    /**
     * @dev Pause/unpause an action on a market
     * @param market Market to pause/unpause the action on
     * @param action Action id to pause/unpause
     * @param paused The new paused state (true=paused, false=unpaused)
     */
    function _setActionPaused(
        address market,
        Action action,
        bool paused
    ) internal {
        require(
            markets[market].isListed,
            "cannot pause a market that is not listed"
        );
        _actionPaused[market][action] = paused;
        emit ActionPausedMarket(LeToken(market), action, paused);
    }

    /**
     * @dev Internal function to check that leTokens can be safely redeemed for the underlying asset.
     * @param leToken Address of the leTokens to redeem
     * @param redeemer Account redeeming the tokens
     * @param redeemTokens The number of tokens to redeem
     */
    function _checkRedeemAllowed(
        address leToken,
        address redeemer,
        uint256 redeemTokens,
        bytes[] calldata priceUpdateData
    ) internal {
        Market storage market = markets[leToken];

        if (!market.isListed) {
            revert MarketNotListed(address(leToken));
        }

        /* If the redeemer is not 'in' the market, then we can bypass the liquidity check */
        if (!market.accountMembership[redeemer]) {
            return;
        }

        // Update the prices of tokens
        updatePrices(redeemer, priceUpdateData);

        /* Otherwise, perform a hypothetical liquidity check to guard against shortfall */
        AccountLiquiditySnapshot
            memory snapshot = _getHypotheticalLiquiditySnapshot(
                redeemer,
                LeToken(leToken),
                redeemTokens,
                0,
                _getCollateralFactor
            );
        if (snapshot.shortfall > 0) {
            revert InsufficientLiquidity();
        }
    }

    /**
     * @notice Get the total collateral, weighted collateral, borrow balance, liquidity, shortfall
     * @param account The account to get the snapshot for
     * @param weight The function to compute the weight of the collateral – either collateral factor or
     *  liquidation threshold. Accepts the address of the leToken and returns the weight as Exp.
     * @dev Note that we calculate the exchangeRateStored for each collateral leToken using stored data,
     *  without calculating accumulated interest.
     * @return snapshot Account liquidity snapshot
     */
    function _getCurrentLiquiditySnapshot(
        address account,
        function(LeToken) internal view returns (Exp memory) weight
    ) internal view returns (AccountLiquiditySnapshot memory snapshot) {
        return
            _getHypotheticalLiquiditySnapshot(
                account,
                LeToken(address(0)),
                0,
                0,
                weight
            );
    }

    /**
     * @notice Determine what the supply/borrow balances would be if the given amounts were redeemed/borrowed
     * @param leTokenModify The market to hypothetically redeem/borrow in
     * @param account The account to determine liquidity for
     * @param redeemTokens The number of tokens to hypothetically redeem
     * @param borrowAmount The amount of underlying to hypothetically borrow
     * @param weight The function to compute the weight of the collateral – either collateral factor or
         liquidation threshold. Accepts the address of the LeToken and returns the weight
     * @dev Note that we calculate the exchangeRateStored for each collateral leToken using stored data,
     *  without calculating accumulated interest.
     * @return snapshot Account liquidity snapshot
     */
    function _getHypotheticalLiquiditySnapshot(
        address account,
        LeToken leTokenModify,
        uint256 redeemTokens,
        uint256 borrowAmount,
        function(LeToken) internal view returns (Exp memory) weight
    ) internal view returns (AccountLiquiditySnapshot memory snapshot) {
        // For each asset the account is in
        LeToken[] memory assets = accountAssets[account];
        uint256 assetsCount = assets.length;

        for (uint256 i; i < assetsCount; ++i) {
            LeToken asset = assets[i];

            // Read the balances and exchange rate from the leToken
            (
                uint256 leTokenBalance,
                uint256 borrowBalance,
                uint256 exchangeRateMantissa
            ) = _safeGetAccountSnapshot(asset, account);

            // Get the normalized price of the asset
            Exp memory oraclePrice = Exp({
                mantissa: _safeGetUnderlyingPrice(asset)
            });

            // Pre-compute conversion factors from leTokens -> usd
            Exp memory leTokenPrice = mul_(
                Exp({mantissa: exchangeRateMantissa}),
                oraclePrice
            );
            Exp memory weightedLeTokenPrice = mul_(weight(asset), leTokenPrice);

            // weightedCollateral += weightedLeTokenPrice * leTokenBalance
            snapshot.weightedCollateral = mul_ScalarTruncateAddUInt(
                weightedLeTokenPrice,
                leTokenBalance,
                snapshot.weightedCollateral
            );

            // totalCollateral += leTokenPrice * leTokenBalance
            snapshot.totalCollateral = mul_ScalarTruncateAddUInt(
                leTokenPrice,
                leTokenBalance,
                snapshot.totalCollateral
            );

            // borrows += oraclePrice * borrowBalance
            snapshot.borrows = mul_ScalarTruncateAddUInt(
                oraclePrice,
                borrowBalance,
                snapshot.borrows
            );

            // Calculate effects of interacting with leTokenModify
            if (asset == leTokenModify) {
                // redeem effect
                // effects += tokensToDenom * redeemTokens
                snapshot.effects = mul_ScalarTruncateAddUInt(
                    weightedLeTokenPrice,
                    redeemTokens,
                    snapshot.effects
                );

                // borrow effect
                // effects += oraclePrice * borrowAmount
                snapshot.effects = mul_ScalarTruncateAddUInt(
                    oraclePrice,
                    borrowAmount,
                    snapshot.effects
                );
            }
        }

        uint256 borrowPlusEffects = snapshot.borrows + snapshot.effects;
        // These are safe, as the underflow condition is checked first
        unchecked {
            if (snapshot.weightedCollateral > borrowPlusEffects) {
                snapshot.liquidity =
                    snapshot.weightedCollateral -
                    borrowPlusEffects;
                snapshot.shortfall = 0;
            } else {
                snapshot.liquidity = 0;
                snapshot.shortfall =
                    borrowPlusEffects -
                    snapshot.weightedCollateral;
            }
        }

        return snapshot;
    }

    /**
     * @dev Retrieves price from oracle for an asset and checks it is nonzero
     * @param asset Address for asset to query price
     * @return Underlying price
     */
    function _safeGetUnderlyingPrice(
        LeToken asset
    ) internal view returns (uint256) {
        uint256 oraclePriceMantissa = oracle.getUnderlyingPrice(address(asset));
        if (oraclePriceMantissa == 0) {
            revert PriceError(address(asset));
        }
        return oraclePriceMantissa;
    }

    /**
     * @dev Return collateral factor for a market
     * @param asset Address for asset
     * @return Collateral factor as exponential
     */
    function _getCollateralFactor(
        LeToken asset
    ) internal view returns (Exp memory) {
        return
            Exp({mantissa: markets[address(asset)].collateralFactorMantissa});
    }

    /**
     * @dev Retrieves liquidation threshold for a market as an exponential
     * @param asset Address for asset to liquidation threshold
     * @return Liquidation threshold as exponential
     */
    function _getLiquidationThreshold(
        LeToken asset
    ) internal view returns (Exp memory) {
        return
            Exp({
                mantissa: markets[address(asset)].liquidationThresholdMantissa
            });
    }

    /**
     * @dev Returns supply and borrow balances of user in leToken, reverts on failure
     * @param leToken Market to query
     * @param user Account address
     * @return leTokenBalance Balance of leTokens, the same as leToken.balanceOf(user)
     * @return borrowBalance Borrowed amount, including the interest
     * @return exchangeRateMantissa Stored exchange rate
     */
    function _safeGetAccountSnapshot(
        LeToken leToken,
        address user
    )
        internal
        view
        returns (
            uint256 leTokenBalance,
            uint256 borrowBalance,
            uint256 exchangeRateMantissa
        )
    {
        uint256 err;
        (err, leTokenBalance, borrowBalance, exchangeRateMantissa) = leToken
            .getAccountSnapshot(user);
        if (err != 0) {
            revert SnapshotError(address(leToken), user);
        }
        return (leTokenBalance, borrowBalance, exchangeRateMantissa);
    }

    /// @notice Reverts if the call is not from expectedSender
    /// @param expectedSender Expected transaction sender
    function _checkSenderIs(address expectedSender) internal view {
        if (msg.sender != expectedSender) {
            revert UnexpectedSender(expectedSender, msg.sender);
        }
    }

    /// @notice Reverts if a certain action is paused on a market
    /// @param market Market to check
    /// @param action Action to check
    function _checkActionPauseState(
        address market,
        Action action
    ) private view {
        if (actionPaused(market, action)) {
            revert ActionPaused(market, action);
        }
    }
}
