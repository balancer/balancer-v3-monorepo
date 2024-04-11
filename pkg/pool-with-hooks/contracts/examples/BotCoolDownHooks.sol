// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IPoolHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IPoolHooks.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { PoolHooks } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { BaseHooks } from "../BaseHooks.sol";

error TooLong(uint256 coolDown);
error TooShort(uint256 coolDown);
error CoolDown();

// solhint-disable not-rely-on-time

/**
 * @title BotCoolDownHooks
 * @notice This contract allows for blocking multiple swaps from the same user within a certain time frame.
 * This can be useful to counteract arbitrage bots.
 */
contract BotCoolDownHooks is BaseHooks, Ownable {
    /// @notice The min available cooldown period.
    uint256 public constant MIN_COOL_DOWN = 5 * 60;

    /// @notice The max available cooldown period.
    uint256 public constant MAX_COOL_DOWN = 42 * 60;

    /// @notice The cooldown period, expressed in seconds, between trades for each trader.
    uint256 public coolDown;

    /// @notice A mapping to track the timestamp of the last trade made by each trader.
    mapping(address => uint256) public lastTrade;

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
                shouldCallBeforeSwap: true,
                shouldCallAfterSwap: false
            }); // Only before swap hook enabled
    }

    function supportsDynamicFee() external pure override returns (bool) {
        return false;
    }

    /// @notice Sets the cooldown period required between trades.
    /// @dev Only callable by the contract owner.
    function setCoolDown(uint256 _coolDown) external onlyOwner {
        if (_coolDown < MIN_COOL_DOWN) revert TooShort(_coolDown);
        if (_coolDown > MAX_COOL_DOWN) revert TooLong(_coolDown);
        coolDown = _coolDown;
    }

    /// @dev Checks if the trader has passed the required cooldown period between trades.
    function _onBeforeSwap(IBasePool.PoolSwapParams memory params) internal virtual override returns (bool) {
        _checkCoolDown(params.sender);
        return true;
    }

    /// @dev Internal function to check if the trader has passed the required cooldown period between trades.
    function _checkCoolDown(address trader) internal {
        if (lastTrade[trader] + coolDown > block.timestamp) revert CoolDown();
        lastTrade[trader] = block.timestamp;
    }
}
