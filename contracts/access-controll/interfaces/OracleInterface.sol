// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.13;

interface OracleInterface {
    function getPrice(address asset) external view returns (uint256);
}

interface ResilientOracleInterface is OracleInterface {
    function updatePrice(
        address leToken,
        bytes[] calldata priceUpdateData
    ) external;

    function updateAssetPrice(
        address asset,
        bytes[] calldata priceUpdateData
    ) external;

    function getUnderlyingPrice(
        address leToken
    ) external view returns (uint256);
}

interface TwapInterface is OracleInterface {
    function updateTwap(address asset) external returns (uint256);
}

interface BoundValidatorInterface {
    function validatePriceWithAnchorPrice(
        address asset,
        uint256 reporterPrice,
        uint256 anchorPrice
    ) external view returns (bool);
}
