// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.10;

import { Comptroller } from "../Comptroller.sol";
import { LeToken } from "../LeToken.sol";

contract ComptrollerScenario is Comptroller {
    uint256 public blockNumber;

    // solhint-disable-next-line no-empty-blocks
    constructor(address _poolRegistry) Comptroller(_poolRegistry) {}

    function fastForward(uint256 blocks) public returns (uint256) {
        blockNumber += blocks;
        return blockNumber;
    }

    function setBlockNumber(uint256 number) public {
        blockNumber = number;
    }

    function unlist(LeToken leToken) public {
        markets[address(leToken)].isListed = false;
    }

    function membershipLength(LeToken leToken) public view returns (uint256) {
        return accountAssets[address(leToken)].length;
    }
}
