// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.13;

import {LeToken} from "./LeToken.sol";
import {RewardsDistributor} from "./Rewards/RewardsDistributor.sol";
import {ResilientOracleInterface} from "./access-controll/interfaces/OracleInterface.sol";

enum Action {
    MINT,
    REDEEM,
    BORROW,
    REPAY,
    SEIZE,
    LIQUIDATE,
    TRANSFER,
    ENTER_MARKET,
    EXIT_MARKET
}

/**
 * @title ComptrollerInterface
 * @author Kredly
 * @notice Interface implemented by the `Comptroller` contract.
 */
interface ComptrollerInterface {
    /*** Assets You Are In ***/

    function enterMarkets(
        address[] calldata leTokens
    ) external returns (uint256[] memory);

    function exitMarket(
        address leToken,
        bytes[] memory priceUpdateData
    ) external returns (uint256);

    /*** Policy Hooks ***/

    function preMintHook(
        address leToken,
        address minter,
        uint256 mintAmount
    ) external;

    function preRedeemHook(
        address leToken,
        address redeemer,
        uint256 redeemTokens,
        bytes[] calldata priceUpdateData
    ) external;

    function preBorrowHook(
        address leToken,
        address borrower,
        uint256 borrowAmount,
        bytes[] calldata priceUpdateData
    ) external;

    function preRepayHook(
        address leToken,
        address borrower,
        bytes[] calldata priceUpdateData
    ) external;

    function preLiquidateHook(
        address leTokenBorrowed,
        address leTokenCollateral,
        address borrower,
        uint256 repayAmount,
        bool skipLiquidityCheck,
        bytes[] calldata priceUpdateData
    ) external;

    function preSeizeHook(
        address leTokenCollateral,
        address leTokenBorrowed,
        address liquidator,
        address borrower
    ) external;

    function borrowVerify(
        address leToken,
        address borrower,
        uint borrowAmount
    ) external;

    function mintVerify(
        address leToken,
        address minter,
        uint mintAmount,
        uint mintTokens
    ) external;

    function redeemVerify(
        address leToken,
        address redeemer,
        uint redeemAmount,
        uint redeemTokens
    ) external;

    function repayBorrowVerify(
        address leToken,
        address payer,
        address borrower,
        uint repayAmount,
        uint borrowerIndex
    ) external;

    function liquidateBorrowVerify(
        address leTokenBorrowed,
        address leTokenCollateral,
        address liquidator,
        address borrower,
        uint repayAmount,
        uint seizeTokens
    ) external;

    function seizeVerify(
        address leTokenCollateral,
        address leTokenBorrowed,
        address liquidator,
        address borrower,
        uint seizeTokens
    ) external;

    function transferVerify(
        address leToken,
        address src,
        address dst,
        uint transferTokens
    ) external;

    function preTransferHook(
        address leToken,
        address src,
        address dst,
        uint256 transferTokens
    ) external;

    function isComptroller() external view returns (bool);

    /*** Liquidity/Liquidation Calculations ***/

    function liquidateCalculateSeizeTokens(
        address leTokenBorrowed,
        address leTokenCollateral,
        uint256 repayAmount
    ) external view returns (uint256, uint256);

    function getAllMarkets() external view returns (LeToken[] memory);

    function actionPaused(
        address market,
        Action action
    ) external view returns (bool);
}

/**
 * @title ComptrollerViewInterface
 * @author Kredly
 * @notice Interface implemented by the `Comptroller` contract, including only some util view functions.
 */
interface ComptrollerViewInterface {
    function markets(address) external view returns (bool, uint256);

    function oracle() external view returns (ResilientOracleInterface);

    function getAssetsIn(address) external view returns (LeToken[] memory);

    function closeFactorMantissa() external view returns (uint256);

    function liquidationIncentiveMantissa() external view returns (uint256);

    function minLiquidatableCollateral() external view returns (uint256);

    function getRewardDistributors()
        external
        view
        returns (RewardsDistributor[] memory);

    function getAllMarkets() external view returns (LeToken[] memory);

    function borrowCaps(address) external view returns (uint256);

    function supplyCaps(address) external view returns (uint256);

    function approvedDelegates(
        address user,
        address delegate
    ) external view returns (bool);
}
