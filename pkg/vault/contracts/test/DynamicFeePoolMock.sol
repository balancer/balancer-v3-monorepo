// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { TokenConfig, PoolData } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";

import { IBaseDynamicFeePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBaseDynamicFeePool.sol";
import { PoolMock } from "./PoolMock.sol";

contract DynamicFeePoolMock is PoolMock, IBaseDynamicFeePool {
    using FixedPoint for uint256;
    using ScalingHelpers for uint256;

    uint256 internal _swapFeePercentage;

    function _hasDynamicSwapFee() internal pure virtual override returns (bool) {
        return true;
    }

    constructor(
        IVault vault,
        string memory name,
        string memory symbol,
        TokenConfig[] memory tokenConfig,
        bool registerPool,
        uint256 pauseWindowDuration,
        address pauseManager
    ) PoolMock(vault, name, symbol, tokenConfig, registerPool, pauseWindowDuration, pauseManager) {}

    function computeFee(PoolData memory) public view override returns (uint256 dynamicFee) {
        return _swapFeePercentage;
    }

    function setSwapFeePercentage(uint256 swapFeePercentage) external {
        _swapFeePercentage = swapFeePercentage;
    }
}
