// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.13;

/**
 * @title IShortfall
 * @author Kredly
 * @notice Interface implemented by `Shortfall`.
 */
interface IShortfall {
    function convertibleBaseAsset() external returns (address);
}
