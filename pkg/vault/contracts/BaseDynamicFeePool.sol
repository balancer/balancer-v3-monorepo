// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { PoolData } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

/**
 * @dev Pools that implement a dynamic fee need to override this contract methods.
 * TODO: review if needed or it can be removed in favour of just the interface.
 */
abstract contract BaseDynamicFeePool {
    function computeFee(PoolData memory poolData) external view virtual returns (uint256);
}
