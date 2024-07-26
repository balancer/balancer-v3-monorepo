// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IPoolInfo } from "@balancer-labs/v3-interfaces/contracts/pool-utils/IPoolInfo.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { TokenInfo, PoolConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

contract PoolInfo is IPoolInfo {
    IVault private immutable _vault;

    constructor(IVault vault) {
        _vault = vault;
    }

    /// @inheritdoc IPoolInfo
    function getTokens() external view returns (IERC20[] memory tokens) {
        return _vault.getPoolTokens(address(this));
    }

    /// @inheritdoc IPoolInfo
    function getTokenInfo()
        external
        view
        returns (
            IERC20[] memory tokens,
            TokenInfo[] memory tokenInfo,
            uint256[] memory balancesRaw,
            uint256[] memory lastBalancesLiveScaled18
        )
    {
        return _vault.getPoolTokenInfo(address(this));
    }

    /// @inheritdoc IPoolInfo
    function getCurrentLiveBalances() external view returns (uint256[] memory balancesLiveScaled18) {
        return _vault.getCurrentLiveBalances(address(this));
    }

    /// @inheritdoc IPoolInfo
    function getStaticSwapFeePercentage() external view returns (uint256) {
        return _vault.getStaticSwapFeePercentage((address(this)));
    }

    /// @inheritdoc IPoolInfo
    function getAggregateFeePercentages()
        external
        view
        returns (uint256 aggregateSwapFeePercentage, uint256 aggregateYieldFeePercentage)
    {
        PoolConfig memory poolConfig = _vault.getPoolConfig(address(this));

        aggregateSwapFeePercentage = poolConfig.aggregateSwapFeePercentage;
        aggregateYieldFeePercentage = poolConfig.aggregateYieldFeePercentage;
    }
}
