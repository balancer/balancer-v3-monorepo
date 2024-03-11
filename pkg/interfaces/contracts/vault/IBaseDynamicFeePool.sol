// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IBasePool } from "./IBasePool.sol";
import { PoolData } from "./VaultTypes.sol";

/// @notice Interface for a Base Pool with dynamic fees
interface IBaseDynamicFeePool is IBasePool {
    function computeFee(PoolData memory poolData) external view returns (uint256);
}
