// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";

import { IRouterCommon } from "@balancer-labs/v3-interfaces/contracts/vault/IRouterCommon.sol";
import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import { IAllowanceTransfer } from "permit2/src/interfaces/IAllowanceTransfer.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { StorageSlotExtension } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/StorageSlotExtension.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { RevertCodec } from "@balancer-labs/v3-solidity-utils/contracts/helpers/RevertCodec.sol";
import {
    ReentrancyGuardTransient
} from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/ReentrancyGuardTransient.sol";
import { Version } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Version.sol";
import {
    TransientStorageHelpers
} from "@balancer-labs/v3-solidity-utils/contracts/helpers/TransientStorageHelpers.sol";

import { RouterWethLib } from "./lib/RouterWethLib.sol";
import { SenderGuard } from "./SenderGuard.sol";
import { VaultGuard } from "./VaultGuard.sol";

/**
 * @notice Abstract base contract for functions shared among all Routers.
 * @dev Common functionality includes access to the sender (which would normally be obscured, since msg.sender in the
 * Vault is the Router contract itself, not the account that invoked the Router), versioning, and the external
 * invocation functions (`permitBatchAndCall` and `multicall`).
 */
abstract contract RouterCommon is IRouterCommon, SenderGuard, VaultGuard, ReentrancyGuardTransient, Version {
    using Address for address payable;
    using StorageSlotExtension for *;
    using RouterWethLib for IWETH;
    using SafeCast for *;

    // NOTE: If you use a constant, then it is simply replaced everywhere when this constant is used by what is written
    // after =. If you use immutable, the value is first calculated and then replaced everywhere. That means that if a
    // constant has executable variables, they will be executed every time the constant is used.

    // solhint-disable-next-line var-name-mixedcase
    bytes32 private immutable _IS_RETURN_ETH_LOCKED_SLOT =
        TransientStorageHelpers.calculateSlot(type(RouterCommon).name, "isReturnEthLocked");

    // solhint-disable-next-line var-name-mixedcase
    IWETH internal immutable _weth;

    IPermit2 internal immutable _permit2;

    /**
     * @notice Locks the return of excess ETH to the sender until the end of the function.
     * @dev This also encompasses the `saveSender` functionality.
     */
    modifier saveSenderAndManageEth() {
        bool isExternalSender = _saveSender(msg.sender);

        // Revert if a function with this modifier is called recursively (e.g., multicall).
        if (_isReturnEthLockedSlot().tload()) {
            revert ReentrancyGuardReentrantCall();
        }

        // Lock the return of ETH during execution
        _isReturnEthLockedSlot().tstore(true);
        _;
        _isReturnEthLockedSlot().tstore(false);

        address sender = _getSenderSlot().tload();
        _discardSenderIfRequired(isExternalSender);

        _returnEth(sender);
    }

    constructor(
        IVault vault,
        IWETH weth,
        IPermit2 permit2,
        string memory routerVersion
    ) SenderGuard() VaultGuard(vault) Version(routerVersion) {
        _weth = weth;
        _permit2 = permit2;
    }

    /// @inheritdoc IRouterCommon
    function getWeth() external view returns (IWETH) {
        return _weth;
    }

    /// @inheritdoc IRouterCommon
    function getPermit2() external view returns (IPermit2) {
        return _permit2;
    }

    /*******************************************************************************
                                      Utilities
    *******************************************************************************/

    struct SignatureParts {
        bytes32 r;
        bytes32 s;
        uint8 v;
    }

    /// @inheritdoc IRouterCommon
    function permitBatchAndCall(
        PermitApproval[] calldata permitBatch,
        bytes[] calldata permitSignatures,
        IAllowanceTransfer.PermitBatch calldata permit2Batch,
        bytes calldata permit2Signature,
        bytes[] calldata multicallData
    ) external payable virtual returns (bytes[] memory results) {
        _permitBatch(permitBatch, permitSignatures, permit2Batch, permit2Signature);

        // Execute all the required operations once permissions have been granted.
        return multicall(multicallData);
    }

    function _permitBatch(
        PermitApproval[] calldata permitBatch,
        bytes[] calldata permitSignatures,
        IAllowanceTransfer.PermitBatch calldata permit2Batch,
        bytes calldata permit2Signature
    ) internal nonReentrant {
        InputHelpers.ensureInputLengthMatch(permitBatch.length, permitSignatures.length);

        // Use Permit (ERC-2612) to grant allowances to Permit2 for tokens to swap,
        // and grant allowances to Vault for BPT tokens.
        for (uint256 i = 0; i < permitBatch.length; ++i) {
            bytes memory signature = permitSignatures[i];

            SignatureParts memory signatureParts = _getSignatureParts(signature);
            PermitApproval memory permitApproval = permitBatch[i];

            try
                IERC20Permit(permitApproval.token).permit(
                    permitApproval.owner,
                    address(this),
                    permitApproval.amount,
                    permitApproval.deadline,
                    signatureParts.v,
                    signatureParts.r,
                    signatureParts.s
                )
            {
                // solhint-disable-previous-line no-empty-blocks
                // OK; carry on.
            } catch (bytes memory returnData) {
                // Did it fail because the permit was executed (possible DoS attack to make the transaction revert),
                // or was it something else (e.g., deadline, invalid signature)?
                if (
                    IERC20(permitApproval.token).allowance(permitApproval.owner, address(this)) != permitApproval.amount
                ) {
                    // It was something else, or allowance was used, so we should revert. Bubble up the revert reason.
                    RevertCodec.bubbleUpRevert(returnData);
                }
            }
        }

        // Only call permit2 if there's something to do.
        if (permit2Batch.details.length > 0) {
            // Use Permit2 for tokens that are swapped and added into the Vault. Note that this call on Permit2 is
            // theoretically also vulnerable to the same DoS attack as above. This edge case was not mitigated
            // on-chain, mainly due to the increased complexity and cost of protecting the batch call.
            //
            // If this is a concern, we recommend submitting through a private node to avoid front-running the public
            // mempool. In any case, best practice is to always use expiring, limited approvals, and only with known
            // and trusted contracts.
            //
            // See https://www.immunebytes.com/blog/permit2-erc-20-token-approvals-and-associated-risks/.

            _permit2.permit(msg.sender, permit2Batch, permit2Signature);
        }
    }

    /// @inheritdoc IRouterCommon
    function multicall(
        bytes[] calldata data
    ) public payable virtual saveSenderAndManageEth returns (bytes[] memory results) {
        results = new bytes[](data.length);
        for (uint256 i = 0; i < data.length; ++i) {
            results[i] = Address.functionDelegateCall(address(this), data[i]);
        }
        return results;
    }

    function _getSignatureParts(bytes memory signature) private pure returns (SignatureParts memory signatureParts) {
        bytes32 r;
        bytes32 s;
        uint8 v;

        // solhint-disable-next-line no-inline-assembly
        assembly ("memory-safe") {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }

        signatureParts.r = r;
        signatureParts.s = s;
        signatureParts.v = v;
    }

    /**
     * @dev Returns excess ETH back to the contract caller. Checks for sufficient ETH balance are made right before
     * each deposit, ensuring it will revert with a friendly custom error. If there is any balance remaining when
     * `_returnEth` is called, return it to the sender.
     *
     * Because the caller might not know exactly how much ETH a Vault action will require, they may send extra.
     * Note that this excess value is returned *to the contract caller* (msg.sender). If caller and e.g. swap sender
     * are not the same (because the caller is a relayer for the sender), then it is up to the caller to manage this
     * returned ETH.
     */
    function _returnEth(address sender) internal {
        // It's cheaper to check the balance and return early than checking a transient variable.
        // Moreover, most operations will not have ETH to return.
        uint256 excess = address(this).balance;
        if (excess == 0) {
            return;
        }

        // If the return of ETH is locked, then don't return it,
        // because _returnEth will be called again at the end of the call.
        if (_isReturnEthLockedSlot().tload()) {
            return;
        }

        payable(sender).sendValue(excess);
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

    function _takeTokenIn(address sender, IERC20 tokenIn, uint256 amountIn, bool wethIsEth) internal {
        // If the tokenIn is ETH, then wrap `amountIn` into WETH.
        if (wethIsEth && tokenIn == _weth) {
            _weth.wrapEthAndSettle(_vault, amountIn);
        } else {
            if (amountIn > 0) {
                // Send the tokenIn amount to the Vault.
                _permit2.transferFrom(sender, address(_vault), amountIn.toUint160(), address(tokenIn));
                _vault.settle(tokenIn, amountIn);
            }
        }
    }

    function _sendTokenOut(address sender, IERC20 tokenOut, uint256 amountOut, bool wethIsEth) internal {
        if (amountOut == 0) {
            return;
        }

        // If the tokenOut is ETH, then unwrap `amountOut` into ETH.
        if (wethIsEth && tokenOut == _weth) {
            _weth.unwrapWethAndTransferToSender(_vault, sender, amountOut);
        } else {
            // Receive the tokenOut amountOut.
            _vault.sendTo(tokenOut, sender, amountOut);
        }
    }

    function _maxTokenLimits(address pool) internal view returns (uint256[] memory maxLimits) {
        uint256 numTokens = _vault.getPoolTokens(pool).length;
        maxLimits = new uint256[](numTokens);
        for (uint256 i = 0; i < numTokens; ++i) {
            maxLimits[i] = _MAX_AMOUNT;
        }
    }

    function _isReturnEthLockedSlot() internal view returns (StorageSlotExtension.BooleanSlotType) {
        return _IS_RETURN_ETH_LOCKED_SLOT.asBoolean();
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
    receive() external payable virtual {
        if (msg.sender != address(_weth)) {
            revert EthTransfer();
        }
    }
}
