// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";

import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import { IBufferRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IBufferRouter.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import {
    ReentrancyGuardTransient
} from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/ReentrancyGuardTransient.sol";

import { RouterCommon } from "./RouterCommon.sol";

/**
 * @notice Entrypoint for swaps, liquidity operations, and corresponding queries.
 * @dev The external API functions unlock the Vault, which calls back into the corresponding hook functions.
 * These interact with the Vault, transfer tokens, settle accounting, and handle wrapping and unwrapping ETH.
 */
contract BufferRouter is IBufferRouter, RouterCommon, ReentrancyGuardTransient {
    using Address for address;

    constructor(
        IVault vault,
        IWETH weth,
        IPermit2 permit2,
        string memory version
    ) RouterCommon(vault, weth, permit2, version) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /*******************************************************************************
                                  ERC4626 Buffers
    *******************************************************************************/

    /// @inheritdoc IBufferRouter
    function initializeBuffer(
        IERC4626 wrappedToken,
        uint256 amountUnderlying,
        uint256 amountWrapped,
        uint256 minIssuedShares
    ) external returns (uint256 issuedShares) {
        return
            abi.decode(
                _vault.unlock(
                    abi.encodeCall(
                        BufferRouter.initializeBufferHook,
                        (
                            wrappedToken,
                            amountUnderlying,
                            amountWrapped,
                            minIssuedShares,
                            msg.sender // sharesOwner
                        )
                    )
                ),
                (uint256)
            );
    }

    /**
     * @notice Hook for initializing a vault buffer.
     * @dev Can only be called by the Vault. Buffers must be initialized before use.
     * @param wrappedToken Address of the wrapped token that implements IERC4626
     * @param amountUnderlying Amount of underlying tokens that will be deposited into the buffer
     * @param amountWrapped Amount of wrapped tokens that will be deposited into the buffer
     * @param minIssuedShares Minimum amount of shares to receive, in underlying token native decimals
     * @param sharesOwner Address that will own the deposited liquidity. Only this address will be able to
     * remove liquidity from the buffer
     * @return issuedShares the amount of tokens sharesOwner has in the buffer, expressed in underlying token amounts.
     * (This is the BPT of an internal ERC4626 buffer)
     */
    function initializeBufferHook(
        IERC4626 wrappedToken,
        uint256 amountUnderlying,
        uint256 amountWrapped,
        uint256 minIssuedShares,
        address sharesOwner
    ) external nonReentrant onlyVault returns (uint256 issuedShares) {
        issuedShares = _vault.initializeBuffer(
            wrappedToken,
            amountUnderlying,
            amountWrapped,
            minIssuedShares,
            sharesOwner
        );
        _takeTokenIn(sharesOwner, IERC20(wrappedToken.asset()), amountUnderlying, false);
        _takeTokenIn(sharesOwner, IERC20(address(wrappedToken)), amountWrapped, false);
    }

    /// @inheritdoc IBufferRouter
    function addLiquidityToBuffer(
        IERC4626 wrappedToken,
        uint256 maxAmountUnderlyingIn,
        uint256 maxAmountWrappedIn,
        uint256 exactSharesToIssue
    ) external returns (uint256 amountUnderlying, uint256 amountWrapped) {
        return
            abi.decode(
                _vault.unlock(
                    abi.encodeCall(
                        BufferRouter.addLiquidityToBufferHook,
                        (
                            wrappedToken,
                            maxAmountUnderlyingIn,
                            maxAmountWrappedIn,
                            exactSharesToIssue,
                            msg.sender // sharesOwner
                        )
                    )
                ),
                (uint256, uint256)
            );
    }

    /**
     * @notice Hook for adding liquidity to vault buffers. The Vault will enforce that the buffer is initialized.
     * @dev Can only be called by the Vault.
     * @param wrappedToken Address of the wrapped token that implements IERC4626
     * @param exactSharesToIssue The value in underlying tokens that `sharesOwner` wants to add to the buffer,
     * in underlying token decimals
     * @param maxAmountUnderlyingIn Maximum amount of underlying tokens to add to the buffer. It is expressed in
     * underlying token native decimals
     * @param maxAmountWrappedIn Maximum amount of wrapped tokens to add to the buffer. It is expressed in wrapped
     * token native decimals
     * @param sharesOwner Address that will own the deposited liquidity. Only this address will be able to
     * remove liquidity from the buffer
     * @return amountUnderlying Amount of underlying tokens deposited into the buffer
     * @return amountWrapped Amount of wrapped tokens deposited into the buffer
     */
    function addLiquidityToBufferHook(
        IERC4626 wrappedToken,
        uint256 maxAmountUnderlyingIn,
        uint256 maxAmountWrappedIn,
        uint256 exactSharesToIssue,
        address sharesOwner
    ) external nonReentrant onlyVault returns (uint256 amountUnderlying, uint256 amountWrapped) {
        (amountUnderlying, amountWrapped) = _vault.addLiquidityToBuffer(
            wrappedToken,
            maxAmountUnderlyingIn,
            maxAmountWrappedIn,
            exactSharesToIssue,
            sharesOwner
        );
        _takeTokenIn(sharesOwner, IERC20(wrappedToken.asset()), amountUnderlying, false);
        _takeTokenIn(sharesOwner, IERC20(address(wrappedToken)), amountWrapped, false);
    }

    function queryInitializeBuffer(
        IERC4626 wrappedToken,
        uint256 amountUnderlying,
        uint256 amountWrapped
    ) external returns (uint256 issuedShares) {
        return
            abi.decode(
                _vault.quote(
                    abi.encodeCall(
                        BufferRouter.queryInitializeBufferHook,
                        (wrappedToken, amountUnderlying, amountWrapped)
                    )
                ),
                (uint256)
            );
    }

    function queryInitializeBufferHook(
        IERC4626 wrappedToken,
        uint256 amountUnderlying,
        uint256 amountWrapped
    ) external nonReentrant onlyVault returns (uint256 issuedShares) {
        issuedShares = _vault.initializeBuffer(wrappedToken, amountUnderlying, amountWrapped, 0, address(this));
    }

    function queryAddLiquidityToBuffer(
        IERC4626 wrappedToken,
        uint256 exactSharesToIssue
    ) external returns (uint256 amountUnderlying, uint256 amountWrapped) {
        return
            abi.decode(
                _vault.quote(
                    abi.encodeCall(BufferRouter.queryAddLiquidityToBufferHook, (wrappedToken, exactSharesToIssue))
                ),
                (uint256, uint256)
            );
    }

    function queryAddLiquidityToBufferHook(
        IERC4626 wrappedToken,
        uint256 exactSharesToIssue
    ) external nonReentrant onlyVault returns (uint256 amountUnderlying, uint256 amountWrapped) {
        (amountUnderlying, amountWrapped) = _vault.addLiquidityToBuffer(
            wrappedToken,
            type(uint128).max,
            type(uint128).max,
            exactSharesToIssue,
            address(this)
        );
    }

    function queryRemoveLiquidityFromBuffer(
        IERC4626 wrappedToken,
        uint256 sharesToRemove
    ) external returns (uint256 removedUnderlyingBalanceRaw, uint256 removedWrappedBalanceRaw) {
        return
            abi.decode(
                _vault.quote(
                    abi.encodeCall(BufferRouter.queryRemoveLiquidityFromBufferHook, (wrappedToken, sharesToRemove))
                ),
                (uint256, uint256)
            );
    }

    function queryRemoveLiquidityFromBufferHook(
        IERC4626 wrappedToken,
        uint256 sharesToRemove
    ) external returns (uint256 removedUnderlyingBalance, uint256 removedWrappedBalance) {
        return _vault.removeLiquidityFromBuffer(wrappedToken, sharesToRemove, 0, 0);
    }
}
