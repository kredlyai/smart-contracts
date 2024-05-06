// SPDX-License-Identifier: BSD-3-Clause
// SPDX-FileCopyrightText: 2022 Kredly
pragma solidity 0.8.13;

interface SIDRegistryInterface {
    function resolver(bytes32 node) external view returns (address);
}
