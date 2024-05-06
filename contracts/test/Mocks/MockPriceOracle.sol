// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.10;

import {ResilientOracleInterface} from "../../access-controll/interfaces/OracleInterface.sol";
import {LeToken} from "../../LeToken.sol";

contract MockPriceOracle is ResilientOracleInterface {
    mapping(address => uint256) public assetPrices;

    constructor() {}

    function setPrice(address asset, uint256 price) external {
        assetPrices[asset] = price;
    }

    function updatePrice(
        address leToken,
        bytes[] calldata priceUpdateData
    ) external override {}

    function updateAssetPrice(
        address asset,
        bytes[] calldata priceUpdateData
    ) external override {}

    function getPrice(address asset) external view returns (uint256) {
        return assetPrices[asset];
    }

    function getUnderlyingPrice(
        address leToken
    ) public view override returns (uint256) {
        return assetPrices[LeToken(leToken).underlying()];
    }
}
