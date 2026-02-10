// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { TokenConfig, LiquidityManagement } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { AfterSwapParams, SwapKind } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { BaseHooks, HookFlags } from "@balancer-labs/v3-vault/contracts/BaseHooks.sol";
import { VaultGuard } from "@balancer-labs/v3-vault/contracts/VaultGuard.sol";

contract DirectionalSwapFeeTaxHook is BaseHooks, VaultGuard, Ownable2Step {
    using FixedPoint for uint256;
    using SafeERC20 for IERC20;

    uint64 public constant MAX_TAX_PERCENTAGE = 10e16;

    // The token on which to apply the directional swap tax.
    IERC20 private immutable _feeToken;
    // The amount of the tax.
    uint256 private immutable _taxPercentage;

    /**
     * @notice A new `DirectionalSwapFeeTaxHook` contract has been registered successfully.
     * @dev If the registration fails the call will revert, so there will be no event.
     * @param pool The pool on which the hook was registered
     * @param factory The factory that registered the pool
     */
    event DirectionSwapFeeTaxHookRegistered(address indexed pool, address indexed factory);

    /**
     * @notice The hook charged a fee after a swap.
     * @param hook This contract address
     * @param feeToken The token in which the fee is charged
     * @param hookFeeAmount The amount of the fee
     */
    event HookFeeCharged(address indexed hook, IERC20 indexed feeToken, uint256 hookFeeAmount);

    /**
     * @notice The hooks contract owner has withdrawn tokens.
     * @param hooksContract The hooks contract charging the fee
     * @param token The token being withdrawn
     * @param recipient The recipient of the withdrawal (hooks contract owner)
     * @param feeAmount The new hook swap fee percentage
     */
    event HookFeeWithdrawn(
        address indexed hooksContract,
        IERC20 indexed token,
        address indexed recipient,
        uint256 feeAmount
    );

    /// @notice The given fee exceeds the maximum allowed percentage.
    error TaxPercentageTooHigh();

    constructor(
        IVault vault,
        IERC20 feeToken,
        uint256 taxPercentage,
        address owner,
        bool isSecondaryHook
    ) BaseHooks(isSecondaryHook) VaultGuard(vault) Ownable(owner) {
        require(taxPercentage <= MAX_TAX_PERCENTAGE, TaxPercentageTooHigh());

        _feeToken = feeToken;
        _taxPercentage = taxPercentage;
    }

    function getFeeToken() external view returns (IERC20) {
        return _feeToken;
    }

    function getTaxPercentage() external view returns (uint256) {
        return _taxPercentage;
    }

    /// @inheritdoc BaseHooks
    function getHookFlags() public pure override returns (HookFlags memory hookFlags) {
        // `enableHookAdjustedAmounts` must be true for all contracts that modify the `amountCalculated`
        // in after hooks. Otherwise, the Vault will ignore any "hookAdjusted" amounts, and the transaction
        // might not settle. (It should be false if the after hooks do something else.)
        hookFlags.enableHookAdjustedAmounts = true;
        hookFlags.shouldCallAfterSwap = true;
    }

    /***************************************************************************
                                IHooks Functions
    ***************************************************************************/

    /// @inheritdoc BaseHooks
    function onRegister(
        address factory,
        address pool,
        TokenConfig[] memory,
        LiquidityManagement calldata
    ) public override returns (bool) {
        _setAuthorizedCaller(factory, pool, address(_vault));

        emit DirectionSwapFeeTaxHookRegistered(pool, factory);

        return true;
    }

    /// @inheritdoc IHooks
    function onAfterSwap(
        AfterSwapParams calldata params
    ) public override onlyAuthorizedCaller returns (bool success, uint256 hookAdjustedAmountCalculatedRaw) {
        hookAdjustedAmountCalculatedRaw = params.amountCalculatedRaw;

        if (_taxPercentage > 0) {
            IERC20 calculatedFeeToken = params.kind == SwapKind.EXACT_IN ? params.tokenOut : params.tokenIn;

            // Directional - only take a fee on the designated fee token.
            if (address(calculatedFeeToken) == address(_feeToken)) {
                uint256 hookFeeAmount = params.amountCalculatedRaw.mulUp(_taxPercentage);

                if (hookFeeAmount > 0) {
                    // Note that we can only alter the calculated amount in this function. This means that the fee will
                    // be charged in different tokens depending on whether the swap is exact in / out, potentially
                    // breaking the equivalence (i.e., one direction might "cost" less than the other).

                    if (params.kind == SwapKind.EXACT_IN) {
                        // For EXACT_IN swaps, the `amountCalculated` is the amount of `tokenOut`. The fee must be
                        // taken from `amountCalculated`, so we decrease the amount of tokens the Vault will send to
                        // the caller.
                        //
                        // The preceding swap operation has already credited the original `amountCalculated`. Since
                        // we're returning `amountCalculated - hookFeeAmount` here, it will only register debt for that
                        // reduced amount on settlement. This call to `sendTo` pulls `hookFeeAmount` tokens of
                        // `tokenOut` from the Vault to this contract, and registers the additional debt, so that the
                        // total debits match the credits and settlement succeeds.
                        hookAdjustedAmountCalculatedRaw -= hookFeeAmount;
                    } else {
                        // For EXACT_OUT swaps, the `amountCalculated` is the amount of `tokenIn`. The fee must be
                        // taken from `amountCalculated`, so we increase the amount of tokens the Vault will ask from
                        // the user.
                        //
                        // The preceding swap operation has already registered debt for the original
                        // `amountCalculated`. Since we're returning `amountCalculated + hookFeeAmount` here, it will
                        // supply credit for that increased amount on settlement. This call to `sendTo` pulls
                        // `hookFeeAmount` tokens of `tokenIn` from the Vault to this contract, and registers the
                        // additional debt, so that the total debits match the credits and settlement succeeds.
                        hookAdjustedAmountCalculatedRaw += hookFeeAmount;
                    }

                    _vault.sendTo(calculatedFeeToken, address(this), hookFeeAmount);

                    emit HookFeeCharged(address(this), calculatedFeeToken, hookFeeAmount);
                }
            }
        }
        return (true, hookAdjustedAmountCalculatedRaw);
    }

    /**
     * @notice Withdraws the accumulated fees and sends them to the owner.
     * @param feeToken The token with accumulated fees
     */
    function withdrawFees(IERC20 feeToken) external onlyOwner {
        uint256 feeAmount = feeToken.balanceOf(address(this));

        if (feeAmount > 0) {
            feeToken.safeTransfer(owner(), feeAmount);

            emit HookFeeWithdrawn(address(this), feeToken, owner(), feeAmount);
        }
    }
}
