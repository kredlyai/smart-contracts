// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.10;

import {AccessControlManager} from "../access-controll/AccessControlManager.sol";

import {LeToken} from "../LeToken.sol";
import {InterestRateModel} from "../InterestRateModel.sol";

contract LeTokenHarness is LeToken {
    uint256 public blockNumber;
    uint256 public harnessExchangeRate;
    bool public harnessExchangeRateStored;

    mapping(address => bool) public failTransferToAddresses;

    function harnessSetAccrualBlockNumber(
        uint256 accrualBlockNumber_
    ) external {
        accrualBlockNumber = accrualBlockNumber_;
    }

    function harnessSetBlockNumber(uint256 newBlockNumber) external {
        blockNumber = newBlockNumber;
    }

    function harnessFastForward(uint256 blocks) external {
        blockNumber += blocks;
    }

    function harnessSetBalance(address account, uint256 amount) external {
        accountTokens[account] = amount;
    }

    function harnessSetTotalSupply(uint256 totalSupply_) external {
        totalSupply = totalSupply_;
    }

    function harnessSetTotalBorrows(uint256 totalBorrows_) external {
        totalBorrows = totalBorrows_;
    }

    function harnessSetTotalReserves(uint256 totalReserves_) external {
        totalReserves = totalReserves_;
    }

    function harnessExchangeRateDetails(
        uint256 totalSupply_,
        uint256 totalBorrows_,
        uint256 totalReserves_
    ) external {
        totalSupply = totalSupply_;
        totalBorrows = totalBorrows_;
        totalReserves = totalReserves_;
    }

    function harnessSetExchangeRate(uint256 exchangeRate) external {
        harnessExchangeRate = exchangeRate;
        harnessExchangeRateStored = true;
    }

    function harnessSetFailTransferToAddress(address to_, bool fail_) external {
        failTransferToAddresses[to_] = fail_;
    }

    function harnessMintFresh(address account, uint256 mintAmount) external {
        super._mintFresh(account, account, mintAmount);
    }

    function harnessRedeemFresh(
        address payable account,
        uint256 leTokenAmount,
        uint256 underlyingAmount,
        bytes[] calldata priceUpdateData
    ) external {
        super._redeemFresh(
            account,
            account,
            leTokenAmount,
            underlyingAmount,
            priceUpdateData
        );
    }

    function harnessSetAccountBorrows(
        address account,
        uint256 principal,
        uint256 interestIndex
    ) external {
        accountBorrows[account] = BorrowSnapshot({
            principal: principal,
            interestIndex: interestIndex
        });
    }

    function harnessSetBorrowIndex(uint256 borrowIndex_) external {
        borrowIndex = borrowIndex_;
    }

    function harnessBorrowFresh(
        address payable account,
        uint256 borrowAmount,
        bytes[] calldata priceUpdateData
    ) external {
        _borrowFresh(account, account, borrowAmount, priceUpdateData);
    }

    function harnessRepayBorrowFresh(
        address payer,
        address account,
        uint256 repayAmount,
        bytes[] calldata priceUpdateData
    ) external {
        _repayBorrowFresh(payer, account, repayAmount, priceUpdateData);
    }

    function harnessLiquidateBorrowFresh(
        address liquidator,
        address borrower,
        uint256 repayAmount,
        LeToken leTokenCollateral,
        bool skipLiquidityCheck,
        bytes[] calldata priceUpdateData
    ) external {
        _liquidateBorrowFresh(
            liquidator,
            borrower,
            repayAmount,
            leTokenCollateral,
            skipLiquidityCheck,
            priceUpdateData
        );
    }

    function harnessReduceReservesFresh(uint256 spreadAmount) external {
        return _reduceReservesFresh(spreadAmount);
    }

    function harnessSetReserveFactorFresh(
        uint256 newReserveFactorMantissa
    ) external {
        _setReserveFactorFresh(newReserveFactorMantissa);
    }

    function harnessSetInterestRateModelFresh(
        InterestRateModel newInterestRateModel
    ) external {
        _setInterestRateModelFresh(newInterestRateModel);
    }

    function harnessAccountBorrows(
        address account
    ) external view returns (uint256 principal, uint256 interestIndex) {
        BorrowSnapshot memory snapshot = accountBorrows[account];
        return (snapshot.principal, snapshot.interestIndex);
    }

    function getBorrowRateMaxMantissa() external pure returns (uint256) {
        return MAX_BORROW_RATE_MANTISSA;
    }

    function harnessSetInterestRateModel(
        address newInterestRateModelAddress
    ) public {
        interestRateModel = InterestRateModel(newInterestRateModelAddress);
    }

    function harnessCallPreBorrowHook(
        uint256 amount,
        bytes[] calldata priceUpdateData
    ) public {
        comptroller.preBorrowHook(
            address(this),
            msg.sender,
            amount,
            priceUpdateData
        );
    }

    function _doTransferOut(address to, uint256 amount) internal override {
        require(
            failTransferToAddresses[to] == false,
            "HARNESS_TOKEN_TRANSFER_OUT_FAILED"
        );
        return super._doTransferOut(to, amount);
    }

    function _exchangeRateStored() internal view override returns (uint256) {
        if (harnessExchangeRateStored) {
            return harnessExchangeRate;
        }
        return super._exchangeRateStored();
    }

    function _getBlockNumber() internal view override returns (uint256) {
        return blockNumber;
    }
}
