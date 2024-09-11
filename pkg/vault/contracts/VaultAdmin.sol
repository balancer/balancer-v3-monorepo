// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IAuthorizer } from "@balancer-labs/v3-interfaces/contracts/vault/IAuthorizer.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IProtocolFeeController } from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeeController.sol";
import { Rounding } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { Authentication } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Authentication.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { PackedTokenBalance } from "@balancer-labs/v3-solidity-utils/contracts/helpers/PackedTokenBalance.sol";

import { VaultStateBits, VaultStateLib } from "./lib/VaultStateLib.sol";
import { VaultExtensionsLib } from "./lib/VaultExtensionsLib.sol";
import { PoolConfigLib, PoolConfigBits } from "./lib/PoolConfigLib.sol";
import { VaultCommon } from "./VaultCommon.sol";
import { VaultGuard } from "./VaultGuard.sol";

/**
 * @dev Bytecode extension for the Vault containing permissioned functions. Complementary to `VaultExtension`,
 * it has access to the same storage layout as the main vault.
 *
 * The functions in this contract are not meant to be called directly. They must only be called by the Vault
 * via delegate calls, so that any state modifications produced by this contract's code will actually target
 * the main Vault's state.
 *
 * The storage of this contract is in practice unused.
 */
contract VaultAdmin is IVaultAdmin, VaultCommon, Authentication, VaultGuard {
    using PackedTokenBalance for bytes32;
    using PoolConfigLib for PoolConfigBits;
    using VaultStateLib for VaultStateBits;
    using VaultExtensionsLib for IVault;
    using SafeERC20 for IERC20;
    using FixedPoint for uint256;

    // Minimum BPT amount minted upon initialization.
    uint256 internal constant _BUFFER_MINIMUM_TOTAL_SUPPLY = 1e4;

    /// @dev Functions with this modifier can only be delegate-called by the vault.
    modifier onlyVaultDelegateCall() {
        _vault.ensureVaultDelegateCall();
        _;
    }

    /// @dev Functions with this modifier can only be called by the pool creator.
    modifier onlyProtocolFeeController() {
        if (msg.sender != address(_protocolFeeController)) {
            revert SenderNotAllowed();
        }
        _;
    }

    /// @dev Validate aggregate percentage values.
    modifier withValidPercentage(uint256 aggregatePercentage) {
        if (aggregatePercentage > FixedPoint.ONE) {
            revert ProtocolFeesExceedTotalCollected();
        }
        _;
    }

    constructor(
        IVault mainVault,
        uint32 pauseWindowDuration,
        uint32 bufferPeriodDuration,
        uint256 minTradeAmount,
        uint256 minWrapAmount
    ) Authentication(bytes32(uint256(uint160(address(mainVault))))) VaultGuard(mainVault) {
        if (pauseWindowDuration > _MAX_PAUSE_WINDOW_DURATION) {
            revert VaultPauseWindowDurationTooLarge();
        }
        if (bufferPeriodDuration > _MAX_BUFFER_PERIOD_DURATION) {
            revert PauseBufferPeriodDurationTooLarge();
        }

        // solhint-disable-next-line not-rely-on-time
        uint32 pauseWindowEndTime = uint32(block.timestamp) + pauseWindowDuration;

        _vaultPauseWindowEndTime = pauseWindowEndTime;
        _vaultBufferPeriodDuration = bufferPeriodDuration;
        _vaultBufferPeriodEndTime = pauseWindowEndTime + bufferPeriodDuration;

        _MINIMUM_TRADE_AMOUNT = minTradeAmount;
        _MINIMUM_WRAP_AMOUNT = minWrapAmount;
    }

    /*******************************************************************************
                               Constants and immutables
    *******************************************************************************/

    /// @inheritdoc IVaultAdmin
    function vault() external view returns (IVault) {
        return _vault;
    }

    /// @inheritdoc IVaultAdmin
    function getPauseWindowEndTime() external view returns (uint32) {
        return _vaultPauseWindowEndTime;
    }

    /// @inheritdoc IVaultAdmin
    function getBufferPeriodDuration() external view returns (uint32) {
        return _vaultBufferPeriodDuration;
    }

    /// @inheritdoc IVaultAdmin
    function getBufferPeriodEndTime() external view returns (uint32) {
        return _vaultBufferPeriodEndTime;
    }

    /// @inheritdoc IVaultAdmin
    function getMinimumPoolTokens() external pure returns (uint256) {
        return _MIN_TOKENS;
    }

    /// @inheritdoc IVaultAdmin
    function getMaximumPoolTokens() external pure returns (uint256) {
        return _MAX_TOKENS;
    }

    /// @inheritdoc IVaultAdmin
    function getPoolMinimumTotalSupply() external pure returns (uint256) {
        return _POOL_MINIMUM_TOTAL_SUPPLY;
    }

    /// @inheritdoc IVaultAdmin
    function getBufferMinimumTotalSupply() external pure returns (uint256) {
        return _BUFFER_MINIMUM_TOTAL_SUPPLY;
    }

    /// @inheritdoc IVaultAdmin
    function getMinimumTradeAmount() external view returns (uint256) {
        return _MINIMUM_TRADE_AMOUNT;
    }

    /// @inheritdoc IVaultAdmin
    function getMinimumWrapAmount() external view returns (uint256) {
        return _MINIMUM_WRAP_AMOUNT;
    }

    /*******************************************************************************
                                    Vault Pausing
    *******************************************************************************/

    /// @inheritdoc IVaultAdmin
    function isVaultPaused() external view onlyVaultDelegateCall returns (bool) {
        return _isVaultPaused();
    }

    /// @inheritdoc IVaultAdmin
    function getVaultPausedState() external view onlyVaultDelegateCall returns (bool, uint32, uint32) {
        return (_isVaultPaused(), _vaultPauseWindowEndTime, _vaultBufferPeriodEndTime);
    }

    /// @inheritdoc IVaultAdmin
    function pauseVault() external onlyVaultDelegateCall authenticate {
        _setVaultPaused(true);
    }

    /// @inheritdoc IVaultAdmin
    function unpauseVault() external onlyVaultDelegateCall authenticate {
        _setVaultPaused(false);
    }

    /**
     * @dev The contract can only be paused until the end of the Pause Window, and
     * unpaused until the end of the Buffer Period.
     */
    function _setVaultPaused(bool pausing) internal {
        if (_isVaultPaused()) {
            if (pausing) {
                // Already paused, and we're trying to pause it again.
                revert VaultPaused();
            }

            // The Vault can always be unpaused while it's paused.
            // When the buffer period expires, `_isVaultPaused` will return false, so we would be in the outside
            // else clause, where trying to unpause will revert unconditionally.
        } else {
            if (pausing) {
                // Not already paused; we can pause within the window.
                // solhint-disable-next-line not-rely-on-time
                if (block.timestamp >= _vaultPauseWindowEndTime) {
                    revert VaultPauseWindowExpired();
                }
            } else {
                // Not paused, and we're trying to unpause it.
                revert VaultNotPaused();
            }
        }

        VaultStateBits vaultState = _vaultStateBits;
        vaultState = vaultState.setVaultPaused(pausing);
        _vaultStateBits = vaultState;

        emit VaultPausedStateChanged(pausing);
    }

    /*******************************************************************************
                                     Pool Pausing
    *******************************************************************************/

    /// @inheritdoc IVaultAdmin
    function pausePool(address pool) external onlyVaultDelegateCall withRegisteredPool(pool) {
        _setPoolPaused(pool, true);
    }

    /// @inheritdoc IVaultAdmin
    function unpausePool(address pool) external onlyVaultDelegateCall withRegisteredPool(pool) {
        _setPoolPaused(pool, false);
    }

    function _setPoolPaused(address pool, bool pausing) internal {
        _ensureAuthenticatedByRole(pool, _poolRoleAccounts[pool].pauseManager);

        PoolConfigBits config = _poolConfigBits[pool];

        if (_isPoolPaused(pool)) {
            if (pausing) {
                // Already paused, and we're trying to pause it again.
                revert PoolPaused(pool);
            }

            // The pool can always be unpaused while it's paused.
            // When the buffer period expires, `_isPoolPaused` will return false, so we would be in the outside
            // else clause, where trying to unpause will revert unconditionally.
        } else {
            if (pausing) {
                // Not already paused; we can pause within the window.
                // solhint-disable-next-line not-rely-on-time
                if (block.timestamp >= config.getPauseWindowEndTime()) {
                    revert PoolPauseWindowExpired(pool);
                }
            } else {
                // Not paused, and we're trying to unpause it.
                revert PoolNotPaused(pool);
            }
        }

        // Update poolConfigBits.
        _poolConfigBits[pool] = config.setPoolPaused(pausing);

        emit PoolPausedStateChanged(pool, pausing);
    }

    /*******************************************************************************
                                        Fees
    *******************************************************************************/

    /// @inheritdoc IVaultAdmin
    function setStaticSwapFeePercentage(
        address pool,
        uint256 swapFeePercentage
    ) external onlyVaultDelegateCall withRegisteredPool(pool) {
        _ensureAuthenticatedByExclusiveRole(pool, _poolRoleAccounts[pool].swapFeeManager);
        _ensureUnpaused(pool);

        _setStaticSwapFeePercentage(pool, swapFeePercentage);
    }

    /// @inheritdoc IVaultAdmin
    function collectAggregateFees(
        address pool
    )
        public
        onlyVaultDelegateCall
        onlyWhenUnlocked
        onlyProtocolFeeController
        withRegisteredPool(pool)
        returns (uint256[] memory totalSwapFees, uint256[] memory totalYieldFees)
    {
        IERC20[] memory poolTokens = _vault.getPoolTokens(pool);
        uint256 numTokens = poolTokens.length;

        totalSwapFees = new uint256[](numTokens);
        totalYieldFees = new uint256[](numTokens);

        for (uint256 i = 0; i < poolTokens.length; ++i) {
            IERC20 token = poolTokens[i];

            (totalSwapFees[i], totalYieldFees[i]) = _aggregateFeeAmounts[pool][token].fromPackedBalance();

            if (totalSwapFees[i] > 0 || totalYieldFees[i] > 0) {
                // Supply credit for the total amount of fees.
                _aggregateFeeAmounts[pool][token] = 0;
                _supplyCredit(token, totalSwapFees[i] + totalYieldFees[i]);
            }
        }
    }

    /// @inheritdoc IVaultAdmin
    function updateAggregateSwapFeePercentage(
        address pool,
        uint256 newAggregateSwapFeePercentage
    )
        external
        onlyVaultDelegateCall
        withRegisteredPool(pool)
        withValidPercentage(newAggregateSwapFeePercentage)
        onlyProtocolFeeController
    {
        _poolConfigBits[pool] = _poolConfigBits[pool].setAggregateSwapFeePercentage(newAggregateSwapFeePercentage);
    }

    /// @inheritdoc IVaultAdmin
    function updateAggregateYieldFeePercentage(
        address pool,
        uint256 newAggregateYieldFeePercentage
    )
        external
        onlyVaultDelegateCall
        withRegisteredPool(pool)
        withValidPercentage(newAggregateYieldFeePercentage)
        onlyProtocolFeeController
    {
        _poolConfigBits[pool] = _poolConfigBits[pool].setAggregateYieldFeePercentage(newAggregateYieldFeePercentage);
    }

    /// @inheritdoc IVaultAdmin
    function setProtocolFeeController(
        IProtocolFeeController newProtocolFeeController
    ) external onlyVaultDelegateCall authenticate nonReentrant {
        _protocolFeeController = newProtocolFeeController;

        emit ProtocolFeeControllerChanged(newProtocolFeeController);
    }

    /*******************************************************************************
                                    Recovery Mode
    *******************************************************************************/

    /// @inheritdoc IVaultAdmin
    function enableRecoveryMode(address pool) external onlyVaultDelegateCall withRegisteredPool(pool) {
        _ensurePoolNotInRecoveryMode(pool);

        // If the Vault or pool is pausable (and currently paused), this call is permissionless.
        if (_isPoolPaused(pool) == false && _isVaultPaused() == false) {
            // If not permissionless, authenticate with governance.
            _authenticateCaller();
        }

        _setPoolRecoveryMode(pool, true);
    }

    /// @inheritdoc IVaultAdmin
    function disableRecoveryMode(address pool) external onlyVaultDelegateCall withRegisteredPool(pool) authenticate {
        _ensurePoolInRecoveryMode(pool);
        _setPoolRecoveryMode(pool, false);
    }

    /**
     * @dev Reverts if the pool is in recovery mode.
     * @param pool The pool
     */
    function _ensurePoolNotInRecoveryMode(address pool) internal view {
        if (_isPoolInRecoveryMode(pool)) {
            revert PoolInRecoveryMode(pool);
        }
    }

    /**
     * @dev Change the recovery mode state of a pool, and emit an event. Assumes any validation (e.g., whether
     * the proposed state change is consistent) has already been done.
     *
     * @param pool The pool
     * @param recoveryMode The desired recovery mode state
     */
    function _setPoolRecoveryMode(address pool, bool recoveryMode) internal {
        if (recoveryMode == false) {
            _syncPoolBalancesAfterRecoveryMode(pool);
        }

        // Update poolConfigBits. `_writePoolBalancesToStorage` updates *only* balances, not yield fees, which are
        // forfeited during Recovery Mode. To prevent yield fees from being charged, `_loadPoolData` must be called
        // while still in Recovery Mode, so updating the Recovery Mode bit must be done last, after the accounting.
        _poolConfigBits[pool] = _poolConfigBits[pool].setPoolInRecoveryMode(recoveryMode);

        emit PoolRecoveryModeStateChanged(pool, recoveryMode);
    }

    /**
     * @dev Raw and live balances will diverge as tokens are withdrawn during Recovery Mode. Live balances cannot
     * be updated in Recovery Mode, as this would require making external calls to update rates, which could fail.
     * When Recovery Mode is disabled, re-sync the balances.
     */
    function _syncPoolBalancesAfterRecoveryMode(address pool) private nonReentrant {
        _writePoolBalancesToStorage(pool, _loadPoolData(pool, Rounding.ROUND_DOWN));
    }

    /*******************************************************************************
                                        Queries
    *******************************************************************************/

    /// @inheritdoc IVaultAdmin
    function disableQuery() external onlyVaultDelegateCall authenticate {
        VaultStateBits vaultState = _vaultStateBits;
        vaultState = vaultState.setQueryDisabled(true);
        _vaultStateBits = vaultState;

        emit VaultQueriesDisabled();
    }

    /*******************************************************************************
                                  ERC4626 Buffers
    *******************************************************************************/

    /// @inheritdoc IVaultAdmin
    function areBuffersPaused() external view onlyVaultDelegateCall returns (bool) {
        return _vaultStateBits.areBuffersPaused();
    }

    /// @inheritdoc IVaultAdmin
    function pauseVaultBuffers() external onlyVaultDelegateCall authenticate {
        _setVaultBufferPauseState(true);
    }

    /// @inheritdoc IVaultAdmin
    function unpauseVaultBuffers() external onlyVaultDelegateCall authenticate {
        _setVaultBufferPauseState(false);
    }

    function _setVaultBufferPauseState(bool paused) private {
        VaultStateBits vaultState = _vaultStateBits;
        vaultState = vaultState.setBuffersPaused(paused);
        _vaultStateBits = vaultState;

        emit VaultBuffersPausedStateChanged(paused);
    }

    /// @inheritdoc IVaultAdmin
    function initializeBuffer(
        IERC4626 wrappedToken,
        uint256 amountUnderlyingRaw,
        uint256 amountWrappedRaw,
        address sharesOwner
    )
        public
        onlyVaultDelegateCall
        onlyWhenUnlocked
        whenVaultBuffersAreNotPaused
        nonReentrant
        returns (uint256 issuedShares)
    {
        if (_bufferAssets[wrappedToken] != address(0)) {
            revert BufferAlreadyInitialized(wrappedToken);
        }

        address underlyingToken = wrappedToken.asset();

        if (underlyingToken == address(0)) {
            // Should never happen, but a malicious wrapper could return the zero address and cause the buffer
            // initialization code to run more than once.
            revert InvalidUnderlyingToken(wrappedToken);
        }

        // Register asset of wrapper, so it cannot change.
        _bufferAssets[wrappedToken] = underlyingToken;

        // Take debt for initialization assets.
        _takeDebt(IERC20(underlyingToken), amountUnderlyingRaw);
        _takeDebt(wrappedToken, amountWrappedRaw);

        // Update buffer balances.
        _bufferTokenBalances[wrappedToken] = PackedTokenBalance.toPackedBalance(amountUnderlyingRaw, amountWrappedRaw);

        // At initialization, the initial "BPT rate" is 1, so the `issuedShares` is simply the sum of the initial
        // buffer token balances, converted to underlying. We use `previewRedeem` to convert wrapped to underlying,
        // since `redeem` is an EXACT_IN operation that rounds down the result.
        issuedShares = wrappedToken.previewRedeem(amountWrappedRaw) + amountUnderlyingRaw;
        _ensureBufferMinimumTotalSupply(issuedShares);

        // Divide `issuedShares` between the zero address, which receives the minimum supply, and the account
        // depositing the tokens to initialize the buffer, which receives the balance.
        issuedShares -= _BUFFER_MINIMUM_TOTAL_SUPPLY;

        _mintMinimumBufferSupplyReserve(wrappedToken);
        _mintBufferShares(wrappedToken, sharesOwner, issuedShares);

        emit LiquidityAddedToBuffer(wrappedToken, amountUnderlyingRaw, amountWrappedRaw);
    }

    /// @inheritdoc IVaultAdmin
    function addLiquidityToBuffer(
        IERC4626 wrappedToken,
        uint256 amountUnderlyingRaw,
        uint256 amountWrappedRaw,
        address sharesOwner
    )
        public
        onlyVaultDelegateCall
        onlyWhenUnlocked
        whenVaultBuffersAreNotPaused
        withInitializedBuffer(wrappedToken)
        nonReentrant
        returns (uint256 issuedShares)
    {
        // Check wrapped token asset correctness.
        address underlyingToken = wrappedToken.asset();
        _ensureCorrectBufferAsset(wrappedToken, underlyingToken);

        // Take debt for assets going into the buffer (wrapped and underlying).
        _takeDebt(IERC20(underlyingToken), amountUnderlyingRaw);
        _takeDebt(wrappedToken, amountWrappedRaw);

        bytes32 bufferBalances = _bufferTokenBalances[wrappedToken];

        // The buffer invariant is the sum of buffer token balances converted to underlying. We use `previewRedeem` to
        // convert wrapped to underlying, since `redeem` is an EXACT_IN operation that rounds down the result.
        uint256 currentInvariant = bufferBalances.getBalanceRaw() +
            wrappedToken.previewRedeem(bufferBalances.getBalanceDerived());

        // The invariant delta is the amount we're adding (at the current rate) in terms of underlying. We use
        // `previewRedeem` to convert wrapped to underlying, since `redeem` is an EXACT_IN operation that rounds down
        // the result.
        uint256 bufferInvariantDelta = wrappedToken.previewRedeem(amountWrappedRaw) + amountUnderlyingRaw;
        // The new share amount is the invariant ratio normalized by the total supply.
        // Rounds down, as the shares are "outgoing," in the sense that they can be redeemed for tokens.
        issuedShares = (_bufferTotalShares[wrappedToken] * bufferInvariantDelta) / currentInvariant;

        // Add the amountsIn to the current buffer balances.
        bufferBalances = PackedTokenBalance.toPackedBalance(
            bufferBalances.getBalanceRaw() + amountUnderlyingRaw,
            bufferBalances.getBalanceDerived() + amountWrappedRaw
        );
        _bufferTokenBalances[wrappedToken] = bufferBalances;

        // Mint new shares to the owner.
        _mintBufferShares(wrappedToken, sharesOwner, issuedShares);

        emit LiquidityAddedToBuffer(wrappedToken, amountUnderlyingRaw, amountWrappedRaw);
    }

    function _mintMinimumBufferSupplyReserve(IERC4626 wrappedToken) internal {
        _bufferTotalShares[wrappedToken] = _BUFFER_MINIMUM_TOTAL_SUPPLY;
        _bufferLpShares[wrappedToken][address(0)] = _BUFFER_MINIMUM_TOTAL_SUPPLY;

        emit BufferSharesMinted(wrappedToken, address(0), _BUFFER_MINIMUM_TOTAL_SUPPLY);
    }

    function _mintBufferShares(IERC4626 wrappedToken, address to, uint256 amount) internal {
        if (to == address(0)) {
            revert BufferSharesInvalidReceiver();
        }

        uint256 newTotalSupply = _bufferTotalShares[wrappedToken] + amount;

        // This is called on buffer initialization - after the minimum reserve amount has been minted - and during
        // subsequent adds, when we're increasing it, so we do not really need to check it against the minimum.
        // We do it anyway out of an abundance of caution, and to preserve symmetry with `_burnBufferShares`.
        _ensureBufferMinimumTotalSupply(newTotalSupply);

        _bufferTotalShares[wrappedToken] = newTotalSupply;
        _bufferLpShares[wrappedToken][to] += amount;

        emit BufferSharesMinted(wrappedToken, to, amount);
    }

    /// @inheritdoc IVaultAdmin
    function removeLiquidityFromBuffer(
        IERC4626 wrappedToken,
        uint256 sharesToRemove
    ) external onlyVaultDelegateCall returns (uint256 removedUnderlyingBalanceRaw, uint256 removedWrappedBalanceRaw) {
        return
            abi.decode(
                _vault.unlock(
                    abi.encodeCall(VaultAdmin.removeLiquidityFromBufferHook, (wrappedToken, sharesToRemove, msg.sender))
                ),
                (uint256, uint256)
            );
    }

    /**
     * @dev Internal hook for `removeLiquidityFromBuffer`. Can only be called by the Vault itself via
     * `removeLiquidityFromBuffer`, which correctly forwards the real sender as the `sharesOwner`.
     * This function must be reentrant because it calls the nonReentrant function `sendTo`. However,
     * since `sendTo` is the only function that makes external calls, `removeLiquidityFromBufferHook`
     * cannot reenter the Vault.
     *
     * @param wrappedToken Address of the wrapped token that implements IERC4626
     * @param sharesToRemove Amount of shares to remove from the buffer. Cannot be greater than sharesOwner's
     * total shares
     * @param sharesOwner Owner of the shares (`msg.sender` for `removeLiquidityFromBuffer` entrypoint)
     * @return removedUnderlyingBalanceRaw Amount of underlying tokens returned to the user
     * @return removedWrappedBalanceRaw Amount of wrapped tokens returned to the user
     */
    function removeLiquidityFromBufferHook(
        IERC4626 wrappedToken,
        uint256 sharesToRemove,
        address sharesOwner
    )
        external
        onlyVaultDelegateCall
        onlyVault
        onlyWhenUnlocked
        withInitializedBuffer(wrappedToken)
        returns (uint256 removedUnderlyingBalanceRaw, uint256 removedWrappedBalanceRaw)
    {
        if (sharesToRemove > _bufferLpShares[wrappedToken][sharesOwner]) {
            revert NotEnoughBufferShares();
        }

        bytes32 bufferBalances = _bufferTokenBalances[wrappedToken];
        uint256 totalShares = _bufferTotalShares[wrappedToken];

        removedUnderlyingBalanceRaw = (bufferBalances.getBalanceRaw() * sharesToRemove) / totalShares;
        removedWrappedBalanceRaw = (bufferBalances.getBalanceDerived() * sharesToRemove) / totalShares;

        // We get the underlying token stored internally as opposed to calling `asset()` in the wrapped token.
        // This is to avoid any kind of unnecessary external call; the underlying token is set during initialization
        // and can't change afterwards, so it is already validated at this point. There is no way to add liquidity
        // with an asset that differs from the one set during initialization.
        IERC20 underlyingToken = IERC20(_bufferAssets[wrappedToken]);
        _supplyCredit(underlyingToken, removedUnderlyingBalanceRaw);
        _supplyCredit(wrappedToken, removedWrappedBalanceRaw);

        bufferBalances = PackedTokenBalance.toPackedBalance(
            bufferBalances.getBalanceRaw() - removedUnderlyingBalanceRaw,
            bufferBalances.getBalanceDerived() - removedWrappedBalanceRaw
        );

        _bufferTokenBalances[wrappedToken] = bufferBalances;

        // Ensures we cannot drop the supply below the minimum.
        _burnBufferShares(wrappedToken, sharesOwner, sharesToRemove);

        // This triggers an external call to itself; the vault is acting as a Router in this case.
        // `sendTo` makes external calls (`transfer`) but is non-reentrant.
        _vault.sendTo(underlyingToken, sharesOwner, removedUnderlyingBalanceRaw);
        _vault.sendTo(wrappedToken, sharesOwner, removedWrappedBalanceRaw);

        emit LiquidityRemovedFromBuffer(wrappedToken, removedUnderlyingBalanceRaw, removedWrappedBalanceRaw);
    }

    function _burnBufferShares(IERC4626 wrappedToken, address from, uint256 amount) internal {
        if (from == address(0)) {
            revert BufferSharesInvalidOwner();
        }

        uint256 newTotalSupply = _bufferTotalShares[wrappedToken] - amount;

        // Ensure that the buffer can never be drained below the minimum total supply.
        _ensureBufferMinimumTotalSupply(newTotalSupply);

        _bufferTotalShares[wrappedToken] = newTotalSupply;
        _bufferLpShares[wrappedToken][from] -= amount;

        emit BufferSharesBurned(wrappedToken, from, amount);
    }

    /// @inheritdoc IVaultAdmin
    function getBufferAsset(
        IERC4626 wrappedToken
    ) external view onlyVaultDelegateCall returns (address underlyingToken) {
        return _bufferAssets[wrappedToken];
    }

    /// @inheritdoc IVaultAdmin
    function getBufferOwnerShares(
        IERC4626 token,
        address user
    ) external view onlyVaultDelegateCall returns (uint256 shares) {
        return _bufferLpShares[token][user];
    }

    /// @inheritdoc IVaultAdmin
    function getBufferTotalShares(IERC4626 token) external view onlyVaultDelegateCall returns (uint256 shares) {
        return _bufferTotalShares[token];
    }

    /// @inheritdoc IVaultAdmin
    function getBufferBalance(IERC4626 token) external view onlyVaultDelegateCall returns (uint256, uint256) {
        // The first balance is underlying, and the last is wrapped balance.
        return (_bufferTokenBalances[token].getBalanceRaw(), _bufferTokenBalances[token].getBalanceDerived());
    }

    function _ensureBufferMinimumTotalSupply(uint256 newTotalSupply) private pure {
        if (newTotalSupply < _BUFFER_MINIMUM_TOTAL_SUPPLY) {
            revert BufferTotalSupplyTooLow(newTotalSupply);
        }
    }

    /*******************************************************************************
                                Authentication
    *******************************************************************************/

    /// @inheritdoc IVaultAdmin
    function setAuthorizer(IAuthorizer newAuthorizer) external onlyVaultDelegateCall authenticate {
        _authorizer = newAuthorizer;

        emit AuthorizerChanged(newAuthorizer);
    }

    /// @dev Authenticate by role; otherwise fall through and check governance.
    function _ensureAuthenticatedByRole(address pool, address roleAddress) private view {
        if (msg.sender == roleAddress) {
            return;
        }

        _ensureAuthenticated(pool);
    }

    /// @dev Authenticate exclusively by role; caller must match the `roleAddress`, if assigned.
    function _ensureAuthenticatedByExclusiveRole(address pool, address roleAddress) private view {
        if (roleAddress == address(0)) {
            // Defer to governance if no role assigned.
            _ensureAuthenticated(pool);
        } else if (msg.sender != roleAddress) {
            revert SenderNotAllowed();
        }
    }

    /// @dev Delegate authentication to governance.
    function _ensureAuthenticated(address pool) private view {
        bytes32 actionId = getActionId(msg.sig);

        if (_canPerform(actionId, msg.sender, pool) == false) {
            revert SenderNotAllowed();
        }
    }

    /// @dev Access control is delegated to the Authorizer.
    function _canPerform(bytes32 actionId, address user) internal view override returns (bool) {
        return _authorizer.canPerform(actionId, user, address(this));
    }

    /// @dev Access control is delegated to the Authorizer. `where` refers to the target contract.
    function _canPerform(bytes32 actionId, address user, address where) internal view returns (bool) {
        return _authorizer.canPerform(actionId, user, where);
    }

    /*******************************************************************************
                                     Default handlers
    *******************************************************************************/

    receive() external payable {
        revert CannotReceiveEth();
    }

    // solhint-disable no-complex-fallback

    fallback() external payable {
        if (msg.value > 0) {
            revert CannotReceiveEth();
        }

        revert("Not implemented");
    }
}
