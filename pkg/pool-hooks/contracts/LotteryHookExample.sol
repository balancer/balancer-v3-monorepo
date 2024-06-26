// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IRouterCommon } from "@balancer-labs/v3-interfaces/contracts/vault/IRouterCommon.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {
    AddLiquidityKind,
    LiquidityManagement,
    RemoveLiquidityKind,
    SwapKind,
    TokenConfig
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { BasePoolHooks } from "@balancer-labs/v3-vault/contracts/BasePoolHooks.sol";

contract LotteryHookExample is BasePoolHooks, Ownable {
    using FixedPoint for uint256;

    // Trusted router is needed since we rely on getSender() to know which user should receive the prize.
    address private immutable _trustedRouter;

    // When calling onAfterSwap, a random number is generated. If the number is equal to LUCKY_NUMBER, the user will
    // get the accrued fees.
    uint8 public constant LUCKY_NUMBER = 17;
    uint8 public constant MAX_NUMBER = 100;

    // Percentages are represented as 18-decimal FP, with maximum value of 1e18 (100%), so 60 bits are enough.
    uint64 public hookSwapFeePercentage;

    uint256 private _counter = 0;

    // This hook relies on the implementation of router's getSender() to deposit fees to the winner of the lottery.
    error RouterNotTrustedByHook(address hook, address router);

    constructor(IVault vault, address router) BasePoolHooks(vault) Ownable(msg.sender) {
        _trustedRouter = router;
    }

    /// @inheritdoc IHooks
    function onRegister(
        address,
        address,
        TokenConfig[] memory,
        LiquidityManagement calldata
    ) external view override onlyVault returns (bool) {
        // NOTICE: In real hooks, make sure this function is properly implemented (e.g. check the factory, and check
        // that the given pool is from the factory). Returning true allows any pool, with any configuration, to use
        // this hook
        return true;
    }

    /// @inheritdoc IHooks
    function getHookFlags() external pure override returns (HookFlags memory) {
        HookFlags memory hookFlags;
        // `enableHookAdjustedAmounts` must be true for all contracts that modify the `amountCalculated`
        // in after hooks. Otherwise, the Vault will ignore any "hookAdjusted" amounts, and the transaction
        // might not settle. (It should be false if the after hooks do something else.)
        hookFlags.enableHookAdjustedAmounts = true;
        hookFlags.shouldCallAfterSwap = true;
        return hookFlags;
    }

    /// @inheritdoc IHooks
    function onAfterSwap(
        AfterSwapParams calldata params
    ) external override onlyVault returns (bool success, uint256 hookAdjustedAmountCalculatedRaw) {
        if (params.router != _trustedRouter) {
            // If router is not trusted, the hook can't rely on the implementation of getSender(), so the transaction
            // must revert.
            revert RouterNotTrustedByHook(address(this), params.router);
        }

        // Draws a number to see if the user will pay fees or receive all accrued fees.
        uint8 drawnNumber = _getRandomNumber();
        // Increment counter to modify the drawn number in the next swap.
        _counter++;

        hookAdjustedAmountCalculatedRaw = params.amountCalculatedRaw;
        if (hookSwapFeePercentage > 0) {
            uint256 hookFee = params.amountCalculatedRaw.mulDown(hookSwapFeePercentage);
            if (params.kind == SwapKind.EXACT_IN) {
                // For EXACT_IN swaps, the `amountCalculated` is the amount of `tokenOut`. The fee must be taken
                // from `amountCalculated`, so we decrease the amount of tokens the Vault will send to the caller.
                //
                // The preceding swap operation has already credited the original `amountCalculated`. Since we're
                // returning `amountCalculated - hookFee` here, it will only register debt for that reduced amount
                // on settlement. This call to `sendTo` pulls `hookFee` tokens of `tokenOut` from the Vault to this
                // contract, and registers the additional debt, so that the total debts match the credits and
                // settlement succeeds.
                uint256 feeToPay = _chargeFeeOrPayWinner(params.router, drawnNumber, params.tokenOut, hookFee);
                if (feeToPay > 0) {
                    hookAdjustedAmountCalculatedRaw -= feeToPay;
                }
            } else {
                // For EXACT_OUT swaps, the `amountCalculated` is the amount of `tokenIn`. The fee must be taken
                // from `amountCalculated`, so we increase the amount of tokens the Vault will ask from the user.
                //
                // The preceding swap operation has already registered debt for the original `amountCalculated`.
                // Since we're returning `amountCalculated + hookFee` here, it will supply credit for that increased
                // amount on settlement. This call to `sendTo` pulls `hookFee` tokens of `tokenIn` from the Vault to
                // this contract, and registers the additional debt, so that the total debts match the credits and
                // settlement succeeds.

                uint256 feeToPay = _chargeFeeOrPayWinner(params.router, drawnNumber, params.tokenIn, hookFee);
                if (feeToPay > 0) {
                    hookAdjustedAmountCalculatedRaw += feeToPay;
                }
            }
        }
        return (true, hookAdjustedAmountCalculatedRaw);
    }

    // Sets the hook swap fee percentage, which will be accrued after a swap was executed. This function must be
    // permissioned.
    function setHookSwapFeePercentage(uint64 feePercentage) external onlyOwner {
        hookSwapFeePercentage = feePercentage;
    }

    function getRandomNumber() external view returns (uint8) {
        return _getRandomNumber();
    }

    // @notice
    function _chargeFeeOrPayWinner(
        address router,
        uint8 drawnNumber,
        IERC20 token,
        uint256 hookFee
    ) private returns (uint256) {
        if (drawnNumber == LUCKY_NUMBER) {
            address user = IRouterCommon(router).getSender();
            // The total accrued fees may be higher than the amountIn, so we can't use deltas to pay the fees to the
            // winner when the swap is EXACT_OUT (To pay the fees, we'd need to give a discount, and the max discount
            // is 100%, which is amountsIn).
            // To avoid this limitation, we transfer the tokens to the user directly.
            token.transfer(user, token.balanceOf(address(this)));
            return 0;
        } else {
            _vault.sendTo(token, address(this), hookFee);
            return hookFee;
        }
    }

    // @notice Generates a "random" number from 1 to MAX_NUMBER
    // @dev Be aware that, for real applications, the random number must be generated with a help of an oracle, or
    // other off-chain method. The output of this function is predictable.
    function _getRandomNumber() private view returns (uint8) {
        return uint8((uint(keccak256(abi.encodePacked(block.prevrandao, _counter))) % MAX_NUMBER) + 1);
    }
}
