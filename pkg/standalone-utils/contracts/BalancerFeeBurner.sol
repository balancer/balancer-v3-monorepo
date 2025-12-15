// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IProtocolFeeBurner } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IProtocolFeeBurner.sol";
import { IBalancerFeeBurner } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IBalancerFeeBurner.sol";
import { IProtocolFeeSweeper } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IProtocolFeeSweeper.sol";
import { SwapPathStep } from "@balancer-labs/v3-interfaces/contracts/vault/BatchRouterTypes.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import {
    ReentrancyGuardTransient
} from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/ReentrancyGuardTransient.sol";
import { VaultGuard } from "@balancer-labs/v3-vault/contracts/VaultGuard.sol";

import { FeeBurnerAuthentication } from "./FeeBurnerAuthentication.sol";

contract BalancerFeeBurner is IBalancerFeeBurner, ReentrancyGuardTransient, VaultGuard, FeeBurnerAuthentication {
    using SafeERC20 for IERC20;

    mapping(IERC20 => SwapPathStep[]) private _burnSteps;

    constructor(
        IVault vault,
        IProtocolFeeSweeper _protocolFeeSweeper,
        address initialOwner
    ) VaultGuard(vault) FeeBurnerAuthentication(_protocolFeeSweeper, initialOwner) {
        protocolFeeSweeper = _protocolFeeSweeper;
    }

    /// @inheritdoc IBalancerFeeBurner
    function setBurnPath(IERC20 feeToken, SwapPathStep[] calldata steps) external onlyFeeRecipientOrOwner {
        delete _burnSteps[feeToken];

        IERC20 stepTokenIn = feeToken;
        for (uint256 i = 0; i < steps.length; i++) {
            SwapPathStep memory step = steps[i];

            if (step.isBuffer) {
                bool isUnwrap = step.pool == address(stepTokenIn);
                IERC4626 wrappedToken = IERC4626(step.pool);
                address underlyingToken = _vault.getERC4626BufferAsset(wrappedToken);
                if (underlyingToken == address(0)) {
                    revert BufferNotInitialized(step.pool);
                }

                if (isUnwrap && step.tokenOut != IERC20(underlyingToken)) {
                    revert InvalidBufferTokenOut(step.tokenOut, i);
                } else if (isUnwrap == false && step.tokenOut != IERC20(address(wrappedToken))) {
                    revert InvalidBufferTokenOut(step.tokenOut, i);
                }
            } else {
                // Reverts if pool is not registered.
                IERC20[] memory poolTokens = _vault.getPoolTokens(step.pool);
                if (_tokenExists(stepTokenIn, poolTokens) == false) {
                    revert TokenDoesNotExistInPool(stepTokenIn, i);
                } else if (_tokenExists(step.tokenOut, poolTokens) == false) {
                    revert TokenDoesNotExistInPool(step.tokenOut, i);
                }
            }

            stepTokenIn = step.tokenOut;

            _burnSteps[feeToken].push(steps[i]);
        }
    }

    /// @inheritdoc IBalancerFeeBurner
    function getBurnPath(IERC20 feeToken) external view returns (SwapPathStep[] memory steps) {
        return _getBurnPath(feeToken);
    }

    function _getBurnPath(IERC20 feeToken) internal view returns (SwapPathStep[] memory steps) {
        steps = _burnSteps[feeToken];

        if (steps.length == 0) {
            revert BurnPathDoesNotExist();
        }
    }

    /// @inheritdoc IProtocolFeeBurner
    function burn(
        address pool,
        IERC20 feeToken,
        uint256 feeTokenAmount,
        IERC20 targetToken,
        uint256 minAmountOut,
        address recipient,
        uint256 deadline
    ) external onlyProtocolFeeSweeper {
        _vault.unlock(
            abi.encodeCall(
                BalancerFeeBurner.burnHook,
                BurnHookParams({
                    pool: pool,
                    sender: msg.sender,
                    feeToken: feeToken,
                    feeTokenAmount: feeTokenAmount,
                    targetToken: targetToken,
                    minAmountOut: minAmountOut,
                    recipient: recipient,
                    deadline: deadline
                })
            )
        );
    }

    function burnHook(BurnHookParams calldata params) external nonReentrant onlyVault {
        // The deadline is timestamp-based: it should not be relied upon for sub-minute accuracy.
        // solhint-disable-next-line not-rely-on-time
        if (block.timestamp > params.deadline) {
            revert SwapDeadline();
        }

        IERC20 feeToken = params.feeToken;
        IERC20 targetToken = params.targetToken;
        uint256 feeTokenAmount = params.feeTokenAmount;

        SwapPathStep[] memory steps = _getBurnPath(feeToken);
        uint256 lastStepIndex = steps.length - 1;
        if (steps[lastStepIndex].tokenOut != targetToken) {
            revert TargetTokenOutMismatch();
        }

        // Transfer the `tokenIn` to the vault.
        feeToken.safeTransferFrom(params.sender, address(_vault), feeTokenAmount);
        _vault.settle(feeToken, feeTokenAmount);

        // Swap the fee token for the target token through the steps.
        IERC20 stepTokenIn = feeToken;
        uint256 stepExactAmountIn = feeTokenAmount;
        for (uint256 i = 0; i < steps.length; i++) {
            SwapPathStep memory step = steps[i];

            uint256 amountOut;
            uint256 minAmountOut = (i == lastStepIndex) ? params.minAmountOut : 0;
            if (step.isBuffer) {
                (, , amountOut) = _vault.erc4626BufferWrapOrUnwrap(
                    BufferWrapOrUnwrapParams({
                        kind: SwapKind.EXACT_IN,
                        direction: step.pool == address(stepTokenIn)
                            ? WrappingDirection.UNWRAP
                            : WrappingDirection.WRAP,
                        wrappedToken: IERC4626(step.pool),
                        amountGivenRaw: stepExactAmountIn,
                        limitRaw: minAmountOut
                    })
                );
            } else {
                (, , amountOut) = _vault.swap(
                    VaultSwapParams({
                        kind: SwapKind.EXACT_IN,
                        pool: step.pool,
                        tokenIn: stepTokenIn,
                        tokenOut: step.tokenOut,
                        amountGivenRaw: stepExactAmountIn,
                        limitRaw: minAmountOut,
                        userData: bytes("")
                    })
                );
            }

            stepTokenIn = step.tokenOut;
            stepExactAmountIn = amountOut;
        }

        // Last stepTokenIn is the final token out. Last stepExactAmountIn is the amount out.
        _vault.sendTo(stepTokenIn, params.recipient, stepExactAmountIn);

        emit ProtocolFeeBurned(params.pool, feeToken, feeTokenAmount, targetToken, stepExactAmountIn, params.recipient);
    }

    function _tokenExists(IERC20 token, IERC20[] memory tokens) private pure returns (bool) {
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == token) {
                return true;
            }
        }

        return false;
    }
}
