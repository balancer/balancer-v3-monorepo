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

import { EnumerableMap } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/EnumerableMap.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { BasePoolHooks } from "@balancer-labs/v3-vault/contracts/BasePoolHooks.sol";

// In this example, every time a swap is executed in a pool registered with this hook, a "random" number is drawn.
// If the drawn number is not equal to the LUCKY_NUMBER, the user will pay fees to the hook contract. But, if the
// drawn number is equal to LUCKY_NUMBER, the user won't pay hook fees and will receive all fees accrued by the hook.
contract LotteryHookExample is BasePoolHooks, Ownable {
    using FixedPoint for uint256;
    using EnumerableMap for EnumerableMap.IERC20ToUint256Map;

    // Trusted router is needed since we rely on getSender() to know which user should receive the prize.
    address private immutable _trustedRouter;

    // When calling onAfterSwap, a random number is generated. If the number is equal to LUCKY_NUMBER, the user will
    // get the accrued fees. It must be a number between 1 and MAX_NUMBER, or else nobody will win.
    uint8 public constant LUCKY_NUMBER = 10;
    // The chance of winning is 1/MAX_NUMBER (i.e. 5%)
    uint8 public constant MAX_NUMBER = 20;

    // Percentages are represented as 18-decimal FP, with maximum value of 1e18 (100%), so 60 bits are enough.
    uint64 public hookSwapFeePercentage;

    // Tokens with accrued fees
    EnumerableMap.IERC20ToUint256Map private _tokensWithAccruedFees;

    uint256 private _counter = 0;

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
        // this hook.
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
        uint8 drawnNumber;
        if (params.router == _trustedRouter) {
            // If router is trusted, draws a number to be able to get the accrued fees. (If router is not trusted, the
            // user can perform swaps and contribute to the pot, but is not eligible to win.)
            drawnNumber = _getRandomNumber();
        }

        // Increment counter to help randomize the drawn number in the next swap.
        _counter++;

        hookAdjustedAmountCalculatedRaw = params.amountCalculatedRaw;
        if (hookSwapFeePercentage > 0) {
            uint256 hookFee = params.amountCalculatedRaw.mulDown(hookSwapFeePercentage);
            if (params.kind == SwapKind.EXACT_IN) {
                // For EXACT_IN swaps, the `amountCalculated` is the amount of `tokenOut`. The fee must be taken
                // from `amountCalculated`, so we decrease the amount of tokens the Vault will send to the caller.
                //
                // The preceding swap operation has already credited the original `amountCalculated`. Since we're
                // returning `amountCalculated - feeToPay` here, it will only register debt for that reduced amount
                // on settlement. This call to `sendTo` pulls `feeToPay` tokens of `tokenOut` from the Vault to this
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
                // Since we're returning `amountCalculated + feeToPay` here, it will supply credit for that increased
                // amount on settlement. This call to `sendTo` pulls `feeToPay` tokens of `tokenIn` from the Vault to
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

    // @dev This external function was created to allow the test to access the same random number that will be used by
    // onAfterSwap hook, so we can predict whether the current call is a winner. In real applications, this function
    // should not exist, or should return a different number every time, even if called in the same transaction.
    function getRandomNumber() external view returns (uint8) {
        return _getRandomNumber();
    }

    // @notice If drawnNumber = LUCKY_NUMBER, user wins the pot and pay no fees. Else, user adds the hook fee to the
    // pot.
    function _chargeFeeOrPayWinner(
        address router,
        uint8 drawnNumber,
        IERC20 token,
        uint256 hookFee
    ) private returns (uint256) {
        if (drawnNumber == LUCKY_NUMBER) {
            address user = IRouterCommon(router).getSender();

            for (uint256 i = _tokensWithAccruedFees.size; i > 0; i--) {
                (IERC20 feeToken, ) = _tokensWithAccruedFees.at(i - 1);
                _tokensWithAccruedFees.remove(feeToken);

                // There are multiple reasons to use a direct transfer of hook fees to the user instead of hook
                // adjusted amounts:
                // * We can transfer all fees from all tokens;
                // * For EXACT_OUT transactions, the maximum prize we might give is amountsIn, because the maximum
                //   discount is 100%;
                // * We don't need to send tokens to the vault and then settle, which would be more expensive than
                //   transferring tokens to the user directly.
                feeToken.safeTransfer(user, feeToken.balanceOf(address(this)));
            }
            // Winner pays no fees
            return 0;
        } else {
            // add token to map of tokens with accrued fees
            _tokensWithAccruedFees.set(token, 1);

            // Collect fees from the vault (user will pay it when the router settles the swap)
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
