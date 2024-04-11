// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { AddLiquidityKind } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { PoolHooks } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { BaseHooks } from "../BaseHooks.sol";

error ZeroAddress();
error NotAllowedTrader(address trader);
error NotAllowedLp(address liquidityProvider);

interface ITradeAllowance {
    function addTrader(address trader) external returns (bool);

    function removeTrader(address trader) external returns (bool);

    function isAllowedTrader(address trader) external view returns (bool);

    function isAllowedLp(address lp) external view returns (bool);
}

/**
 * @title PrivateTradeHooks
 * @notice This contract implements restricted access logic to the pool.
 *         It can be used, for example, for applying KYC (Know Your Customer) checks
 *         for traders and liquidity providers.
 */
contract PrivateTradeHooks is BaseHooks {
    ITradeAllowance public immutable tradeAllowance;

    constructor(address _tradeAllowance) {
        if (_tradeAllowance == address(0)) revert ZeroAddress();
        tradeAllowance = ITradeAllowance(_tradeAllowance);
    }

    function availableHooks() external pure override returns (PoolHooks memory) {
        return
            PoolHooks({
                shouldCallBeforeInitialize: false,
                shouldCallAfterInitialize: false,
                shouldCallBeforeAddLiquidity: true,
                shouldCallAfterAddLiquidity: false,
                shouldCallBeforeRemoveLiquidity: false,
                shouldCallAfterRemoveLiquidity: false,
                shouldCallBeforeSwap: false,
                shouldCallAfterSwap: false
            }); // Only before add liquidity hook enabled
    }

    /**
     * @notice Ensures that the user adding liquidity is allowed to do so
     *         based on the permissions granted by the trade allowance contract.
     */
    function _onBeforeAddLiquidity(
        address,
        AddLiquidityKind,
        uint256[] memory,
        uint256,
        uint256[] memory,
        bytes memory
    ) internal virtual override returns (bool) {
        if (!tradeAllowance.isAllowedLp(tx.origin)) {
            revert NotAllowedLp(tx.origin);
        }
        return true;
    }

    /**
     * @notice Ensures that the user performing the swap is allowed to do so
     *         based on the permissions granted by the trade allowance contract.
     */
    function _onBeforeSwap(IBasePool.PoolSwapParams memory) internal virtual override returns (bool) {
        if (!tradeAllowance.isAllowedTrader(tx.origin)) {
            revert NotAllowedTrader(tx.origin);
        }
        return true;
    }
}
