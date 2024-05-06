// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.13;

/**
 * @title PoolRegistryInterface
 * @author Kredly
 * @notice Interface implemented by `PoolRegistry`.
 */
interface PoolRegistryInterface {
    /**
     * @notice Struct for a Kredly interest rate pool.
     */
    struct KredlyPool {
        string name;
        address creator;
        address comptroller;
        uint256 blockPosted;
        uint256 timestampPosted;
    }

    /**
     * @notice Struct for a Kredly interest rate pool metadata.
     */
    struct kredlyPoolMetaData {
        string category;
        string logoURL;
        string description;
    }

    /// @notice Get all pools in PoolRegistry
    function getAllPools() external view returns (KredlyPool[] memory);

    /// @notice Get a pool by comptroller address
    function getPoolByComptroller(address comptroller) external view returns (KredlyPool memory);

    /// @notice Get the address of the LeToken contract in the Pool where the underlying token is the provided asset
    function getLeTokenForAsset(address comptroller, address asset) external view returns (address);

    /// @notice Get the addresss of the Pools supported that include a market for the provided asset
    function getPoolsSupportedByAsset(address asset) external view returns (address[] memory);

    /// @notice Get the metadata of a Pool by comptroller address
    function getkredlyPoolMetadata(address comptroller) external view returns (kredlyPoolMetaData memory);
}
