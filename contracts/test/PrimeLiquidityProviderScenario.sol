pragma solidity 0.8.13;

import { PrimeLiquidityProvider } from "../access-controll/PrimeLiquidityProvider.sol";

contract PrimeLiquidityProviderScenario is PrimeLiquidityProvider {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(bool _timeBased, uint256 _blocksPerYear) PrimeLiquidityProvider(_timeBased, _blocksPerYear) {}
}
