// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";

import { ERC20PoolToken } from "@balancer-labs/v3-solidity-utils/contracts/token/ERC20PoolToken.sol";
import { TemporarilyPausable } from "@balancer-labs/v3-solidity-utils/contracts/helpers/TemporarilyPausable.sol";

/// @notice Reference implementation for the base layer of a Pool contract.
abstract contract BasePool is IBasePool, ERC20PoolToken, TemporarilyPausable {
    IVault internal immutable _vault;

    uint256 private constant _DEFAULT_MINIMUM_BPT = 1e6;
    uint256 private constant _SWAP_FEE_PERCENTAGE = 0;

    constructor(
        IVault vault,
        string memory name,
        string memory symbol,
        uint256 pauseWindowDuration,
        uint256 bufferPeriodDuration
    ) ERC20PoolToken(vault, name, symbol) TemporarilyPausable(pauseWindowDuration, bufferPeriodDuration) {
        _vault = vault;
    }

    function _getTotalTokens() internal view virtual returns (uint256);

    /**
     * @notice Return the current value of the swap fee percentage.
     *
     * @return The swap fee percentage
     */
    function getSwapFeePercentage() public pure virtual returns (uint256) {
        return _SWAP_FEE_PERCENTAGE;
    }

    /// @inheritdoc IBasePool
    function getPoolTokens() external view returns (IERC20[] memory tokens, uint256[] memory balances) {
        return _vault.getPoolTokens(address(this));
    }

    /*******************************************************************************
                              Temporarily Pausable
    *******************************************************************************/

    /**
     * @notice Pause the pool: an emergency action which disables all pool functions.
     * @dev This is a permissioned function that will only work during the Pause Window set during pool factory
     * deployment (see `TemporarilyPausable`).
     */
    function pause() external {
        _pause();
    }

    /**
     * @notice Reverse a `pause` operation, and restore a pool to normal functionality.
     * @dev This is a permissioned function that will only work on a paused pool within the Buffer Period set during
     * pool factory deployment (see `TemporarilyPausable`). Note that any paused pools will automatically unpause
     * after the Buffer Period expires.
     */
    function unpause() external {
        _unpause();
    }

    /*******************************************************************************
                                     Callbacks
    *******************************************************************************/

    /// @notice Callback performed after a swap. Reverts here if configured but unimplemented.
    function onAfterSwap(SwapParams calldata, uint256) external view virtual returns (bool) {
        revert CallbackNotImplemented();
    }

    /// @notice Callback performed after adding liquidity. Reverts here if configured but unimplemented.
    function onAfterAddLiquidity(
        address,
        uint256[] memory,
        bytes memory,
        uint256[] memory,
        uint256
    ) external view virtual returns (bool) {
        revert CallbackNotImplemented();
    }

    /// @notice Callback performed after removing liquidity. Reverts here if configured but unimplemented.
    function onAfterRemoveLiquidity(
        address,
        uint256[] memory,
        uint256,
        bytes memory,
        uint256[] memory
    ) external view virtual returns (bool) {
        revert CallbackNotImplemented();
    }
}
