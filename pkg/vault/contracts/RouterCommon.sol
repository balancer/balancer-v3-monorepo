// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IRouter.sol";
import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import { IRouterSender } from "@balancer-labs/v3-interfaces/contracts/vault/IRouterSender.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { StorageSlot } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/StorageSlot.sol";

contract RouterCommon is IRouterSender {
    using Address for address payable;
    using SafeERC20 for IWETH;
    using StorageSlot for *;

    address private _sender;

    /// @dev Incoming ETH transfer from an address that is not WETH.
    error EthTransfer();

    /// @dev The amount of ETH paid is insufficient to complete this operation.
    error InsufficientEth();

    /// @dev The swap transaction was not validated before the specified deadline timestamp.
    error SwapDeadline();

    // Raw token balances are stored in half a slot, so the max is uint128. Moreover, given amounts are usually scaled
    // inside the Vault, so sending max uint256 would result in an overflow and revert.
    uint256 internal constant _MAX_AMOUNT = type(uint128).max;

    IVault internal immutable _vault;

    // solhint-disable-next-line var-name-mixedcase
    IWETH internal immutable _weth;

    IPermit2 internal immutable _permit2;

    modifier onlyVault() {
        _ensureOnlyVault();
        _;
    }

    function _ensureOnlyVault() private view {
        if (msg.sender != address(_vault)) {
            revert IVaultErrors.SenderIsNotVault(msg.sender);
        }
    }

    constructor(IVault vault, IWETH weth, IPermit2 permit2) {
        _vault = vault;
        _weth = weth;
        _permit2 = permit2;
        weth.approve(address(_vault), type(uint256).max);
    }

    /**
     * @dev Returns excess ETH back to the contract caller, assuming `amountUsed` has been spent. Reverts
     * if the caller sent less ETH than `amountUsed`.
     *
     * Because the caller might not know exactly how much ETH a Vault action will require, they may send extra.
     * Note that this excess value is returned *to the contract caller* (msg.sender). If caller and e.g. swap sender are
     * not the same (because the caller is a relayer for the sender), then it is up to the caller to manage this
     * returned ETH.
     */
    function _returnEth(address sender, uint256 amountUsed) internal {
        if (msg.value < amountUsed) {
            revert InsufficientEth();
        }

        uint256 excess = msg.value - amountUsed;
        if (excess > 0) {
            payable(sender).sendValue(excess);
        }
    }

    /**
     * @dev Returns an array with `amountGiven` at `tokenIndex`, and 0 for every other index.
     * The returned array length matches the number of tokens in the pool.
     * Reverts if the given index is greater than or equal to the pool number of tokens.
     */
    function _getSingleInputArrayAndTokenIndex(
        address pool,
        IERC20 token,
        uint256 amountGiven
    ) internal view returns (uint256[] memory amountsGiven, uint256 tokenIndex) {
        uint256 numTokens;
        (numTokens, tokenIndex) = _vault.getPoolTokenCountAndIndexOfToken(pool, token);
        amountsGiven = new uint256[](numTokens);
        amountsGiven[tokenIndex] = amountGiven;
    }

    function _takeTokenIn(
        address sender,
        IERC20 tokenIn,
        uint256 amountIn,
        bool wethIsEth
    ) internal returns (uint256 ethAmountIn) {
        // If the tokenIn is ETH, then wrap `amountIn` into WETH.
        if (wethIsEth && tokenIn == _weth) {
            ethAmountIn = amountIn;
            // wrap amountIn to WETH
            _weth.deposit{ value: amountIn }();
            // send WETH to Vault
            _weth.safeTransfer(address(_vault), amountIn);
            // update Vault accounting
            _vault.settle(_weth);
        } else {
            // Send the tokenIn amount to the Vault
            _permit2.transferFrom(sender, address(_vault), uint160(amountIn), address(tokenIn));
            _vault.settle(tokenIn);
        }
    }

    function _sendTokenOut(address sender, IERC20 tokenOut, uint256 amountOut, bool wethIsEth) internal {
        // If the tokenOut is ETH, then unwrap `amountOut` into ETH.
        if (wethIsEth && tokenOut == _weth) {
            // Receive the WETH amountOut
            _vault.sendTo(tokenOut, address(this), amountOut);
            // Withdraw WETH to ETH
            _weth.withdraw(amountOut);
            // Send ETH to sender
            payable(sender).sendValue(amountOut);
        } else {
            // Receive the tokenOut amountOut
            _vault.sendTo(tokenOut, sender, amountOut);
        }
    }

    /**
     * @dev Enables the Router to receive ETH. This is required for it to be able to unwrap WETH, which sends ETH to the
     * caller.
     *
     * Any ETH sent to the Router outside of the WETH unwrapping mechanism would be forever locked inside the Router, so
     * we prevent that from happening. Other mechanisms used to send ETH to the Router (such as being the recipient of
     * an ETH swap, Pool exit or withdrawal, contract self-destruction, or receiving the block mining reward) will
     * result in locked funds, but are not otherwise a security or soundness issue. This check only exists as an attempt
     * to prevent user error.
     */
    receive() external payable {
        if (msg.sender != address(_weth)) {
            revert EthTransfer();
        }
    }

    /// @inheritdoc IRouterSender
    function getSender() external view returns (address) {
        return _getSenderSlot().tload();
    }

    /**
     * @notice Save the sender address and call a function on Router.
     * @dev Only the first call to this function will save the sender address.
     * Other calls within one transaction can't change the sender.
     * @return result The result of the function call
     */
    function saveSenderAndCall(bytes calldata data) external returns (bytes memory result) {
        StorageSlot.AddressSlotType senderSlot = _getSenderSlot();
        address sender = senderSlot.tload();

        // NOTE: This is a one-time operation. The sender can't be changed within the one transaction.
        if (sender == address(0)) {
            senderSlot.tstore(msg.sender);
        }

        result = Address.functionDelegateCall(address(this), data);
    }

    // solhint-disable no-inline-assembly
    function _getSenderSlot() internal pure returns (StorageSlot.AddressSlotType) {
        StorageSlot.AddressSlotType slot;

        assembly {
            slot := _sender.slot
        }

        return slot;
    }
}
