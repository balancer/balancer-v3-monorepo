// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IProtocolFeeBurner } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IProtocolFeeBurner.sol";
import { IBalancerFeeBurner } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IBalancerFeeBurner.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import {
    ReentrancyGuardTransient
} from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/ReentrancyGuardTransient.sol";
import { SingletonAuthentication } from "@balancer-labs/v3-vault/contracts/SingletonAuthentication.sol";

contract BalancerFeeBurner is IBalancerFeeBurner, ReentrancyGuardTransient, SingletonAuthentication {
    using SafeERC20 for IERC20;

    mapping(IERC20 => SwapPathStep[] steps) internal _burnSteps;

    constructor(IVault vault) SingletonAuthentication(vault) {
        // solhint-disable-previous-line no-empty-blocks
    }

    modifier onlyVault() {
        _ensureOnlyVault();
        _;
    }

    /// @inheritdoc IBalancerFeeBurner
    function setBurnPath(IERC20 feeToken, SwapPathStep[] calldata steps) external authenticate {
        delete _burnSteps[feeToken];

        for (uint256 i = 0; i < steps.length; i++) {
            _burnSteps[feeToken].push(steps[i]);
        }
    }

    function getBurnPath(IERC20 feeToken) public view returns (SwapPathStep[] memory steps) {
        steps = _burnSteps[feeToken];

        if (steps.length == 0) {
            revert BurnPathNotExists();
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
    ) external authenticate {
        getVault().unlock(
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

        SwapPathStep[] memory steps = getBurnPath(feeToken);
        uint256 lastStepIndex = steps.length - 1;
        if (steps[lastStepIndex].tokenOut != targetToken) {
            revert TargetTokenInPathNotTheSame();
        }

        IVault vault = getVault();

        // Transfer the token in to the vault.
        feeToken.safeTransferFrom(params.sender, address(vault), feeTokenAmount);
        vault.settle(feeToken, feeTokenAmount);

        // Swap the fee token for the target token through the steps.
        IERC20 stepTokenIn = feeToken;
        uint256 stepExactAmountIn = feeTokenAmount;
        for (uint256 i = 0; i < steps.length; i++) {
            SwapPathStep memory step = steps[i];

            (, , uint256 amountOut) = vault.swap(
                VaultSwapParams({
                    kind: SwapKind.EXACT_IN,
                    pool: step.pool,
                    tokenIn: stepTokenIn,
                    tokenOut: step.tokenOut,
                    amountGivenRaw: stepExactAmountIn,
                    limitRaw: (i == lastStepIndex) ? params.minAmountOut : 0,
                    userData: bytes("")
                })
            );

            stepTokenIn = step.tokenOut;
            stepExactAmountIn = amountOut;
        }

        address recipient = params.recipient;
        // Last stepTokenIn is the final token out. Last stepExactAmountIn is the amount out.
        vault.sendTo(stepTokenIn, recipient, stepExactAmountIn);

        emit ProtocolFeeBurned(params.pool, feeToken, feeTokenAmount, targetToken, stepExactAmountIn, recipient);
    }

    function _ensureOnlyVault() private view {
        if (msg.sender != address(getVault())) {
            revert IVaultErrors.SenderIsNotVault(msg.sender);
        }
    }
}
