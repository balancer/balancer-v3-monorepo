// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { ISenderGuard } from "@balancer-labs/v3-interfaces/contracts/vault/ISenderGuard.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPCommon.sol";

import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { BaseHooks } from "@balancer-labs/v3-vault/contracts/BaseHooks.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { LBPValidation } from "./LBPValidation.sol";

abstract contract LBPCommon is ILBPCommon, Ownable2Step, BaseHooks {
    using FixedPoint for uint256;

    // The sale parameters are timestamp-based: they should not be relied upon for sub-minute accuracy.
    // solhint-disable not-rely-on-time

    // LBPs are constrained to two tokens: project and reserve.
    uint256 internal constant _TWO_TOKENS = 2;

    // LBPools are deployed with the Balancer standard router address, which we know reliably reports the true sender.
    address internal immutable _trustedRouter;

    // The project token is the one being launched (i.e., sold).
    IERC20 internal immutable _projectToken;
    // The reserve token is the starting capital (and proceeds), and is usually a stablecoin or WETH.
    IERC20 internal immutable _reserveToken;

    // For convenience, we also store the corresponding token indices.
    uint256 internal immutable _projectTokenIndex;
    uint256 internal immutable _reserveTokenIndex;

    // These times mark the time boundaries of the sale.
    // Liquidity can only be added before the start, and removed after the end.
    uint256 internal immutable _startTime;
    uint256 internal immutable _endTime;

    // If true, project tokens can only be bought, not sold back to the pool; i.e., they cannot be
    // the `tokenIn` of a swap.
    bool internal immutable _blockProjectTokenSwapsIn;

    // Vault state used by the redeemability checks.
    IVault internal immutable _lbpVault;
    uint256 internal immutable _poolMinimumTotalSupply;
    uint256 internal immutable _minimumTradeAmount;

    // Minimum non-zero balance a swap may leave behind.
    uint256 internal immutable _minRedeemableBalanceScaled18;

    /// @notice Swaps are disabled except during the sale (i.e., between and start and end times).
    error SwapsDisabled();

    /**
     * @notice A swap would leave a token balance that cannot be fully redeemed.
     * @param tokenIndex Index of the affected token
     * @param endingBalanceScaled18 Resulting balance, or a conservative lower bound
     * @param minBalanceScaled18 Minimum allowed non-zero balance
     */
    error TokenBalanceBlocksRedemption(uint256 tokenIndex, uint256 endingBalanceScaled18, uint256 minBalanceScaled18);

    /**
     * @notice Initialization would produce a state that cannot be fully redeemed.
     * @param totalSupply The resulting pool token supply
     */
    error InitialStateBlocksRedemption(uint256 totalSupply);

    /**
     * @notice A proportional add would produce a state that cannot be fully redeemed.
     * @param totalSupply The resulting pool token supply
     */
    error ResultingStateBlocksRedemption(uint256 totalSupply);

    /**
     * @notice A proportional removal would leave too little circulating supply to redeem.
     * @param remainingCirculatingSupply The remaining circulating pool token supply
     */
    error RemainingSupplyBlocksRedemption(uint256 remainingCirculatingSupply);

    /**
     * @notice A proportional removal would leave a token balance that cannot be fully redeemed.
     * @param tokenIndex Index of the affected token
     * @param remainingBalanceScaled18 The remaining token balance
     * @param remainingSupply The remaining pool token supply
     */
    error RemainingBalanceBlocksRedemption(
        uint256 tokenIndex,
        uint256 remainingBalanceScaled18,
        uint256 remainingSupply
    );

    /// @notice Removing liquidity is not allowed before the end of the sale.
    error RemovingLiquidityNotAllowed();

    /// @notice The pool does not allow adding liquidity except during initialization and before the weight update.
    error AddingLiquidityNotAllowed();

    /// @notice The LBP configuration prohibits selling the project token back into the pool.
    error SwapOfProjectTokenIn();

    /// @notice Single token liquidity operations (that call `computeBalance` are unsupported.
    error UnsupportedOperation();

    /// @notice Only allow adding liquidity (including initialization) before the sale.
    modifier onlyBeforeSale() {
        if (block.timestamp >= _startTime) {
            revert AddingLiquidityNotAllowed();
        }
        _;
    }

    constructor(
        LBPCommonParams memory lbpCommonParams,
        address trustedRouter,
        IVault vault
    ) Ownable(lbpCommonParams.owner) {
        LBPValidation.validateCommonParams(lbpCommonParams);

        // Cache the Vault minimums used by the redeemability checks.
        uint256 poolMinimumTotalSupply = vault.getPoolMinimumTotalSupply();
        uint256 minimumTradeAmount = vault.getMinimumTradeAmount();

        _lbpVault = vault;
        _poolMinimumTotalSupply = poolMinimumTotalSupply;
        _minimumTradeAmount = minimumTradeAmount;
        _minRedeemableBalanceScaled18 = poolMinimumTotalSupply + minimumTradeAmount;

        // Set the trusted router (passed down from the factory), and the rest of the immutable variables.
        _trustedRouter = trustedRouter;

        _projectToken = lbpCommonParams.projectToken;
        _reserveToken = lbpCommonParams.reserveToken;

        _startTime = lbpCommonParams.startTime;
        _endTime = lbpCommonParams.endTime;

        _blockProjectTokenSwapsIn = lbpCommonParams.blockProjectTokenSwapsIn;

        (_projectTokenIndex, _reserveTokenIndex) = lbpCommonParams.projectToken < lbpCommonParams.reserveToken
            ? (0, 1)
            : (1, 0);
    }

    /// @inheritdoc ILBPCommon
    function getProjectToken() external view returns (IERC20) {
        return _projectToken;
    }

    /// @inheritdoc ILBPCommon
    function getReserveToken() external view returns (IERC20) {
        return _reserveToken;
    }

    /// @inheritdoc ILBPCommon
    function getTokenIndices() external view returns (uint256, uint256) {
        return (_projectTokenIndex, _reserveTokenIndex);
    }

    /// @inheritdoc ILBPCommon
    function isProjectTokenSwapInBlocked() external view returns (bool) {
        return _blockProjectTokenSwapsIn;
    }

    /// @inheritdoc ILBPCommon
    function getTrustedRouter() external view returns (address) {
        return _trustedRouter;
    }

    /// @inheritdoc ILBPCommon
    function isSwapEnabled() external view returns (bool) {
        return _isSwapEnabled();
    }

    /// @inheritdoc ILBPCommon
    function getMinRedeemableBalance() external view returns (uint256) {
        return _minRedeemableBalanceScaled18;
    }

    /*******************************************************************************
                                      Pool Hooks
    *******************************************************************************/

    /**
     * @notice Hook to be executed when the pool is registered.
     * @dev Returns true if registration was successful; false will revert with `HookRegistrationFailed`.
     * @param pool Address of the pool (must be this contract for LBPs: the pool is also the hook)
     * @param tokenConfig The token configuration of the pool being registered (e.g., type)
     * @return success True if the hook allowed the registration, false otherwise
     */
    function onRegister(
        address,
        address pool,
        TokenConfig[] memory tokenConfig,
        LiquidityManagement calldata liquidityManagement
    ) public view virtual override returns (bool) {
        // These preconditions are guaranteed by the standard LBPoolFactory, but check anyway.
        InputHelpers.ensureInputLengthMatch(_TWO_TOKENS, tokenConfig.length);

        // Ensure there are no "WITH_RATE" tokens. We don't need to check anything else, as the Vault has already
        // ensured we don't have a STANDARD token with a rate provider.
        if (tokenConfig[0].tokenType != TokenType.STANDARD || tokenConfig[1].tokenType != TokenType.STANDARD) {
            revert IVaultErrors.InvalidTokenConfiguration();
        }

        // Redeemability checks assume proportional liquidity operations.
        LBPValidation.validateLiquidityManagement(liquidityManagement);

        return pool == address(this);
    }

    /**
     * @notice Return the HookFlags struct, which indicates which hooks this contract supports.
     * @dev For each flag set to true, the Vault will call the corresponding hook.
     * @return hookFlags Flags indicating which hooks are supported for LBPs
     */
    function getHookFlags() public pure virtual override returns (HookFlags memory hookFlags) {
        // Required to enforce single-LP liquidity provision, and ensure all funding occurs before the sale.
        hookFlags.shouldCallBeforeInitialize = true;
        hookFlags.shouldCallBeforeAddLiquidity = true;

        // Validate redeemability after the Vault has computed the initial supply.
        hookFlags.shouldCallAfterInitialize = true;

        // Required to enforce the liquidity can only be withdrawn after the end of the sale.
        hookFlags.shouldCallBeforeRemoveLiquidity = true;
    }

    /**
     * @notice Block initialization if the sale has already started.
     * @dev Take care to set the start time far enough in advance to allow for funding; otherwise the pool will remain
     * unfunded and need to be redeployed. Note that initialization does not pass the router address, so we cannot
     * directly check that here, though there has to be a call on the trusted router for its `getSender` to be
     * non-zero. Note that this is overridden in all existing LBPools, so this will never be called. We are leaving it
     * in for future LBP types.
     *
     * @return success Always true: allow the initialization to proceed if the time condition has been met
     */
    function onBeforeInitialize(
        uint256[] memory,
        bytes memory
    ) public view virtual override onlyBeforeSale returns (bool) {
        return ISenderGuard(_trustedRouter).getSender() == owner();
    }

    /**
     * @notice Ensure initialization produces a fully redeemable state.
     * @param exactAmountsIn The balances stored after initialization
     * @param bptAmountOut The pool tokens minted to the initializer
     * @return success Always true if the resulting state is valid
     */
    function onAfterInitialize(
        uint256[] memory exactAmountsIn,
        uint256 bptAmountOut,
        bytes memory
    ) public view virtual override returns (bool) {
        uint256 totalSupply = bptAmountOut + _poolMinimumTotalSupply;

        if (bptAmountOut == 0 || _isFullyRedeemable(exactAmountsIn, totalSupply) == false) {
            revert InitialStateBlocksRedemption(totalSupply);
        }

        return true;
    }

    /**
     * @notice Allow the owner to add proportional liquidity before the sale.
     * @param router The router used for the operation
     * @param kind The liquidity add kind
     * @param minBptAmountOut The pool tokens to be minted for a proportional add
     * @param balancesScaled18 The stored balances before the add
     * @return success True if the operation may proceed
     */
    function onBeforeAddLiquidity(
        address router,
        address,
        AddLiquidityKind kind,
        uint256[] memory,
        uint256 minBptAmountOut,
        uint256[] memory balancesScaled18,
        bytes memory
    ) public view virtual override onlyBeforeSale returns (bool) {
        if (router != _trustedRouter || ISenderGuard(router).getSender() != owner()) {
            return false;
        }

        if (kind == AddLiquidityKind.PROPORTIONAL) {
            _ensureAddedStateIsRedeemable(minBptAmountOut, balancesScaled18);
        }

        return true;
    }

    /**
     * @notice Allow liquidity removal before or after the sale, but not during it.
     * @param kind The liquidity removal kind
     * @param maxBptAmountIn The pool tokens to be burned for a proportional removal
     * @param balancesScaled18 The stored balances before the removal
     * @return success True if the operation may proceed
     */
    function onBeforeRemoveLiquidity(
        address,
        address,
        RemoveLiquidityKind kind,
        uint256 maxBptAmountIn,
        uint256[] memory,
        uint256[] memory balancesScaled18,
        bytes memory
    ) public view virtual override returns (bool) {
        // Do not allow removing liquidity during the sale.
        if (block.timestamp >= _startTime && block.timestamp <= _endTime) {
            revert RemovingLiquidityNotAllowed();
        }

        if (kind == RemoveLiquidityKind.PROPORTIONAL) {
            _ensureRemainderIsRedeemable(maxBptAmountIn, balancesScaled18);
        }

        return true;
    }

    /*******************************************************************************
                                  Internal Functions
    *******************************************************************************/

    function _isSwapEnabled() internal view returns (bool) {
        return block.timestamp >= _startTime && block.timestamp <= _endTime;
    }

    /**
     * @notice Ensure a swap leaves the token balance in a redeemable state.
     * @param tokenIndex Index of the affected token
     * @param endingBalanceScaled18 Resulting balance, or a conservative lower bound
     */
    function _ensureBalanceIsRedeemable(uint256 tokenIndex, uint256 endingBalanceScaled18) internal view {
        if (endingBalanceScaled18 != 0 && endingBalanceScaled18 < _minRedeemableBalanceScaled18) {
            revert TokenBalanceBlocksRedemption(tokenIndex, endingBalanceScaled18, _minRedeemableBalanceScaled18);
        }
    }

    /**
     * @notice Ensure a proportional removal preserves full redeemability.
     * @param bptAmountIn The pool tokens to be burned
     * @param balancesScaled18 The stored token balances
     */
    function _ensureRemainderIsRedeemable(uint256 bptAmountIn, uint256[] memory balancesScaled18) internal view {
        uint256 totalSupply = _lbpVault.totalSupply(address(this));

        // Leave invalid burn amounts to the Vault.
        if (bptAmountIn > totalSupply - _poolMinimumTotalSupply) {
            return;
        }

        // Do not restrict operations on an already non-redeemable state.
        if (_isFullyRedeemable(balancesScaled18, totalSupply) == false) {
            return;
        }

        uint256 remainingSupply = totalSupply - bptAmountIn;
        uint256 remainingCirculatingSupply = remainingSupply - _poolMinimumTotalSupply;

        // A full exit leaves no circulating claim.
        if (remainingCirculatingSupply == 0) {
            return;
        }

        // The remaining circulating supply must itself be redeemable.
        if (remainingCirculatingSupply < _minimumTradeAmount) {
            revert RemainingSupplyBlocksRedemption(remainingCirculatingSupply);
        }

        // The pool token supply can exceed 128 bits, so these products need full-precision division.
        uint256 numTokens = balancesScaled18.length;
        for (uint256 i = 0; i < numTokens; ++i) {
            uint256 balance = balancesScaled18[i];
            uint256 remainingBalance = balance - Math.mulDiv(balance, bptAmountIn, totalSupply);
            uint256 amountOut = Math.mulDiv(remainingBalance, remainingCirculatingSupply, remainingSupply);

            // Projected balances are conservative; only an exact zero is exempt.
            if (remainingBalance != 0 && amountOut < _minimumTradeAmount) {
                revert RemainingBalanceBlocksRedemption(i, remainingBalance, remainingSupply);
            }
        }
    }

    /**
     * @notice Ensure a proportional add preserves full redeemability.
     * @param bptAmountOut The pool tokens to be minted
     * @param balancesScaled18 The stored token balances before the add
     */
    function _ensureAddedStateIsRedeemable(uint256 bptAmountOut, uint256[] memory balancesScaled18) internal view {
        uint256 totalSupply = _lbpVault.totalSupply(address(this));

        // Do not restrict an add that may repair an already non-redeemable state.
        if (_isFullyRedeemable(balancesScaled18, totalSupply) == false) {
            return;
        }

        uint256 addedSupply = totalSupply + bptAmountOut;
        uint256 addedCirculatingSupply = addedSupply - _poolMinimumTotalSupply;

        if (addedCirculatingSupply != 0 && addedCirculatingSupply < _minimumTradeAmount) {
            revert ResultingStateBlocksRedemption(addedSupply);
        }

        // The pool token supply can exceed 128 bits, so these products need full-precision division.
        uint256 numTokens = balancesScaled18.length;
        for (uint256 i = 0; i < numTokens; ++i) {
            uint256 balance = balancesScaled18[i];
            uint256 addedBalance = balance + Math.mulDiv(balance, bptAmountOut, totalSupply, Math.Rounding.Ceil);
            uint256 amountOut = Math.mulDiv(addedBalance, addedCirculatingSupply, addedSupply);

            // Projected balances are conservative; only an exact zero is exempt.
            if (addedBalance != 0 && amountOut < _minimumTradeAmount) {
                revert ResultingStateBlocksRedemption(addedSupply);
            }
        }
    }

    /**
     * @notice Return whether all circulating pool tokens can be redeemed proportionally.
     * @param balancesScaled18 The stored token balances
     * @param totalSupply The pool token total supply
     * @return success True if the circulating supply can be fully redeemed
     */
    function _isFullyRedeemable(
        uint256[] memory balancesScaled18,
        uint256 totalSupply
    ) internal view returns (bool success) {
        uint256 circulatingSupply = totalSupply - _poolMinimumTotalSupply;

        if (circulatingSupply == 0) {
            return true;
        }

        if (circulatingSupply < _minimumTradeAmount) {
            return false;
        }

        // The pool token supply can exceed 128 bits, so these products need full-precision division.
        uint256 numTokens = balancesScaled18.length;
        for (uint256 i = 0; i < numTokens; ++i) {
            uint256 amountOut = Math.mulDiv(balancesScaled18[i], circulatingSupply, totalSupply);

            if (amountOut != 0 && amountOut < _minimumTradeAmount) {
                return false;
            }
        }

        return true;
    }

    function _computeScalingFactor(IERC20 token) internal view returns (uint256) {
        return 10 ** (18 - IERC20Metadata(address(token)).decimals());
    }

    function _toScaled18(uint256 amount, uint256 scalingFactor) internal pure returns (uint256) {
        return amount * scalingFactor;
    }

    function _toRaw(uint256 amount, uint256 scalingFactor) internal pure returns (uint256) {
        return amount / scalingFactor;
    }
}
