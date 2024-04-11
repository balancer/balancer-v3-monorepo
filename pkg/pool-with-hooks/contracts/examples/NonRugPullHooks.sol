// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IPoolHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IPoolHooks.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { PoolHooks } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { BaseHooks } from "../BaseHooks.sol";

// solhint-disable not-rely-on-time

error TooSmall();
error OverLimit(uint256 amount);

/**
 * @title NonRugPullHooks
 * @notice This contract provides functionality to enforce sell limits for each pool token,
 *         helping to prevent rug pulls or large-scale token dumping.
 */
contract NonRugPullHooks is BaseHooks, Ownable {
    /// @notice A mapping to track sell limits for each pool token.
    mapping(address => uint256) public tokenSellCaps;

    /// @notice The minimum available sell amount for each token
    uint256 public constant MIN_SELL_AMOUNT = 20e18;

    constructor(address _owner) Ownable(_owner) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function availableHooks() external pure override returns (PoolHooks memory) {
        return
            PoolHooks({
                shouldCallBeforeInitialize: false,
                shouldCallAfterInitialize: false,
                shouldCallBeforeAddLiquidity: false,
                shouldCallAfterAddLiquidity: false,
                shouldCallBeforeRemoveLiquidity: false,
                shouldCallAfterRemoveLiquidity: false,
                shouldCallBeforeSwap: false,
                shouldCallAfterSwap: true
            }); // Only after swap hook enabled
    }

    function supportsDynamicFee() external pure override returns (bool) {
        return false;
    }

    /// @notice Checks the token sell limit after a swap operation.
    /// @param params Parameters of the swap operation.
    function _onAfterSwap(IPoolHooks.AfterSwapParams memory params, uint256) internal virtual override returns (bool) {
        _checkTokenSellCap(address(params.tokenIn), params.amountInScaled18);
        return true;
    }

    /// @notice Sets the maximum sell amount for a specific token. To disable sell limit set _maxSellAmount to 0.
    /// @dev Only callable by the contract owner.
    /// @param _token The address of the token.
    /// @param _maxSellAmount The maximum amount of the token that can be sold.
    function setTokenSellCapAmount(address _token, uint256 _maxSellAmount) external onlyOwner {
        if (_maxSellAmount > 0 && _maxSellAmount < MIN_SELL_AMOUNT) revert TooSmall();
        tokenSellCaps[_token] = _maxSellAmount;
    }

    /// @notice Checks if the trade amount exceeds the token sell limit.
    /// @param token The address of the token being traded.
    /// @param tradeAmount The amount of the token being traded.
    function _checkTokenSellCap(address token, uint256 tradeAmount) internal view {
        uint256 tokenSellCap = tokenSellCaps[token];
        if (tokenSellCap > 0 && tradeAmount > tokenSellCap) revert OverLimit(tradeAmount);
    }
}
