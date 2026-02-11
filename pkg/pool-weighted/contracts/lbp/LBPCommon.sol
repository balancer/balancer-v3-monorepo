// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { IRouterCommon } from "@balancer-labs/v3-interfaces/contracts/vault/IRouterCommon.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { ISenderGuard } from "@balancer-labs/v3-interfaces/contracts/vault/ISenderGuard.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPCommon.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { SecondaryHookPool } from "@balancer-labs/v3-pool-hooks/contracts/utils/SecondaryHookPool.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { BaseHooks } from "@balancer-labs/v3-vault/contracts/BaseHooks.sol";

import { LBPValidation } from "./LBPValidation.sol";

abstract contract LBPCommon is ILBPCommon, Ownable2Step, BaseHooks, SecondaryHookPool {
    using FixedPoint for uint256;

    // The sale parameters are timestamp-based: they should not be relied upon for sub-minute accuracy.
    // solhint-disable not-rely-on-time

    // LBPs are constrained to two tokens: project and reserve.
    uint256 internal constant _TWO_TOKENS = 2;

    // LBPools are deployed with the Balancer standard router address, which we know reliably reports the true sender.
    address internal immutable _trustedRouter;
    // This is a custom router with special permission to withdraw liquidity from an LBP, and lock the BPT.
    address internal immutable _migrationRouter;

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

    // This provides a guarantee of token liquidity after migration; liquidity cannot be withdrawn during this period.
    uint256 internal immutable _lockDurationAfterMigration;
    // The percentage of the final pool value that will be sent in the new Weighted Pool after migration.
    uint256 internal immutable _bptPercentageToMigrate;
    // The weight of the project token in the migrated pool (can be different from the LBP ending weight).
    uint256 internal immutable _migrationWeightProjectToken;
    // The weight of the reserve token in the migrated pool (can be different from the LBP ending weight).
    uint256 internal immutable _migrationWeightReserveToken;

    /// @notice Swaps are disabled except during the sale (i.e., between and start and end times).
    error SwapsDisabled();

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

    // The BaseHooks bool parameter is false here, as the pool itself is a primary hook (expecting to be called by the
    // Vault. The `secondaryPoolContract`, if provided, would initialize it true (if derived from BaseHooks).
    constructor(
        LBPCommonParams memory lbpCommonParams,
        MigrationParams memory migrationParams,
        address trustedRouter,
        address migrationRouter,
        address secondaryHookContract
    ) SecondaryHookPool(secondaryHookContract) Ownable(lbpCommonParams.owner) {
        lbpCommonParams.startTime = LBPValidation.validateCommonParams(lbpCommonParams);

        // wake-disable-next-line unchecked-return-value
        LBPValidation.validateMigrationParams(migrationParams, migrationRouter);

        // Set the trusted router (passed down from the factory), and the rest of the immutable variables.
        _trustedRouter = trustedRouter;
        _migrationRouter = migrationRouter;

        _projectToken = lbpCommonParams.projectToken;
        _reserveToken = lbpCommonParams.reserveToken;

        _startTime = lbpCommonParams.startTime;
        _endTime = lbpCommonParams.endTime;

        _blockProjectTokenSwapsIn = lbpCommonParams.blockProjectTokenSwapsIn;

        (_projectTokenIndex, _reserveTokenIndex) = address(lbpCommonParams.projectToken) <
            address(lbpCommonParams.reserveToken)
            ? (0, 1)
            : (1, 0);

        _lockDurationAfterMigration = migrationParams.lockDurationAfterMigration;
        _bptPercentageToMigrate = migrationParams.bptPercentageToMigrate;
        _migrationWeightProjectToken = migrationParams.migrationWeightProjectToken;
        _migrationWeightReserveToken = migrationParams.migrationWeightReserveToken;
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
    function getMigrationRouter() external view returns (address) {
        return _migrationRouter;
    }

    /// @inheritdoc ILBPCommon
    function getMigrationParameters() external view returns (MigrationParams memory) {
        return
            MigrationParams({
                migrationRouter: _migrationRouter,
                lockDurationAfterMigration: _lockDurationAfterMigration,
                bptPercentageToMigrate: _bptPercentageToMigrate,
                migrationWeightProjectToken: _migrationWeightProjectToken,
                migrationWeightReserveToken: _migrationWeightReserveToken
            });
    }

    /// @inheritdoc ILBPCommon
    function isSwapEnabled() external view returns (bool) {
        return _isSwapEnabled();
    }

    /*******************************************************************************
                                      Pool Hooks
    *******************************************************************************/

    /**
     * @notice Return the HookFlags struct, which indicates which hooks this contract supports.
     * @dev For each flag set to true, the Vault will call the corresponding hook.
     * @return hookFlags Flags indicating which hooks are supported for LBPs
     */
    function getHookFlags() public view virtual override returns (HookFlags memory hookFlags) {
        if (_secondaryHookContract != address(0)) {
            // The hook contract may include hooks the native LBP does not.
            hookFlags = IHooks(_secondaryHookContract).getHookFlags();
        }

        // Required to enforce single-LP liquidity provision, and ensure all funding occurs before the sale.
        hookFlags.shouldCallBeforeInitialize = true;
        hookFlags.shouldCallBeforeAddLiquidity = true;

        // Required to enforce the liquidity can only be withdrawn after the end of the sale.
        hookFlags.shouldCallBeforeRemoveLiquidity = true;
    }

    /**
     * @notice Hook to be executed when the pool is registered.
     * @dev Returns true if registration was successful; false will revert with `HookRegistrationFailed`.
     * @param pool Address of the pool (must be this contract for LBPs: the pool is also the hook)
     * @param tokenConfig The token configuration of the pool being registered (e.g., type)
     * @return success True if the hook allowed the registration, false otherwise
     */
    function onRegister(
        address factory,
        address pool,
        TokenConfig[] memory tokenConfig,
        LiquidityManagement calldata liquidityManagement
    ) public virtual override returns (bool success) {
        // These preconditions are guaranteed by the standard LBPoolFactory, but check anyway.
        InputHelpers.ensureInputLengthMatch(_TWO_TOKENS, tokenConfig.length);

        // Ensure there are no "WITH_RATE" tokens. We don't need to check anything else, as the Vault has already
        // ensured we don't have a STANDARD token with a rate provider.
        if (tokenConfig[0].tokenType != TokenType.STANDARD || tokenConfig[1].tokenType != TokenType.STANDARD) {
            revert IVaultErrors.InvalidTokenConfiguration();
        }

        address vault = address(IRouterCommon(_trustedRouter).getVault());

        _setAuthorizedCaller(factory, pool, vault);

        // This is the pool itself, so the Vault should be calling this, with itself as the pool argument.
        success = pool == address(this) && msg.sender == vault;

        if (success && _secondaryHookContract != address(0)) {
            success = IHooks(_secondaryHookContract).onRegister(factory, pool, tokenConfig, liquidityManagement);
        }
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
        uint256[] memory exactAmountsIn,
        bytes memory userData
    ) public virtual override onlyBeforeSale onlyAuthorizedCaller returns (bool success) {
        success = ISenderGuard(_trustedRouter).getSender() == owner();

        if (success && _secondaryHookShouldCall(BEFORE_INITIALIZE)) {
            success = IHooks(_secondaryHookContract).onBeforeInitialize(exactAmountsIn, userData);
        }
    }

    /// @inheritdoc IHooks
    function onAfterInitialize(
        uint256[] memory exactAmountsIn,
        uint256 bptAmountOut,
        bytes memory userData
    ) public virtual override onlyWithHookContract onlyAuthorizedCaller returns (bool success) {
        // Forward to the secondary hook, if it's present and implements onAfterInitialize.
        return
            _secondaryHookShouldCall(AFTER_INITIALIZE)
                ? IHooks(_secondaryHookContract).onAfterInitialize(exactAmountsIn, bptAmountOut, userData)
                : true;
    }

    /**
     * @notice Allow the owner to add liquidity before the start of the sale.
     * @param router The router used for the operation
     * @param pool Pool address, used to fetch pool information from the Vault (pool config, tokens, etc.)
     * @param kind The add liquidity operation type (e.g., proportional, custom)
     * @param maxAmountsInScaled18 Maximum amounts of input tokens
     * @param minBptAmountOut Minimum amount of output pool tokens
     * @param balancesScaled18 Current pool balances, sorted in token registration order
     * @param userData Optional, arbitrary data sent with the encoded request
     * @return success True (allowing the operation to proceed) if the owner is calling through the trusted router
     */
    function onBeforeAddLiquidity(
        address router,
        address pool,
        AddLiquidityKind kind,
        uint256[] memory maxAmountsInScaled18,
        uint256 minBptAmountOut,
        uint256[] memory balancesScaled18,
        bytes memory userData
    ) public virtual override onlyBeforeSale onlyAuthorizedCaller returns (bool success) {
        success = router == _trustedRouter && ISenderGuard(router).getSender() == owner();

        if (success && _secondaryHookShouldCall(BEFORE_ADD_LIQUIDITY)) {
            success = IHooks(_secondaryHookContract).onBeforeAddLiquidity(
                router,
                pool,
                kind,
                maxAmountsInScaled18,
                minBptAmountOut,
                balancesScaled18,
                userData
            );
        }
    }

    /// @inheritdoc IHooks
    function onAfterAddLiquidity(
        address router,
        address pool,
        AddLiquidityKind kind,
        uint256[] memory amountsInScaled18,
        uint256[] memory amountsInRaw,
        uint256 bptAmountOut,
        uint256[] memory balancesScaled18,
        bytes memory userData
    )
        public
        virtual
        override
        onlyWithHookContract
        onlyAuthorizedCaller
        returns (bool success, uint256[] memory hookAdjustedAmountsInRaw)
    {
        // Forward to the secondary hook, if it's present and implements onAfterAddLiquidity.
        return
            _secondaryHookShouldCall(AFTER_ADD_LIQUIDITY)
                ? IHooks(_secondaryHookContract).onAfterAddLiquidity(
                    router,
                    pool,
                    kind,
                    amountsInScaled18,
                    amountsInRaw,
                    bptAmountOut,
                    balancesScaled18,
                    userData
                )
                : (true, amountsInRaw);
    }

    /**
     * @notice Only remove liquidity before the sale (to correct mistakes) or after the sale (withdrawal of proceeds).
     * @param router The address (usually a router contract) that initiated a remove liquidity operation on the Vault
     * @param pool Pool address, used to fetch pool information from the Vault (pool config, tokens, etc.)
     * @param kind The type of remove liquidity operation (e.g., proportional, custom)
     * @param maxBptAmountIn Maximum amount of input pool tokens
     * @param minAmountsOutScaled18 Minimum output amounts, sorted in token registration order
     * @param balancesScaled18 Current pool balances, sorted in token registration order
     * @param userData Optional, arbitrary data sent with the encoded request
     * @return success Always true; if removing liquidity is not allowed, revert here with a more specific error
     */
    function onBeforeRemoveLiquidity(
        address router,
        address pool,
        RemoveLiquidityKind kind,
        uint256 maxBptAmountIn,
        uint256[] memory minAmountsOutScaled18,
        uint256[] memory balancesScaled18,
        bytes memory userData
    ) public virtual override onlyAuthorizedCaller returns (bool success) {
        // Do not allow removing liquidity during the sale.
        if (block.timestamp >= _startTime && block.timestamp <= _endTime) {
            revert RemovingLiquidityNotAllowed();
        }

        success = _migrationRouter == address(0) || router == _migrationRouter;

        if (success && _secondaryHookShouldCall(BEFORE_REMOVE_LIQUIDITY)) {
            success = IHooks(_secondaryHookContract).onBeforeRemoveLiquidity(
                router,
                pool,
                kind,
                maxBptAmountIn,
                minAmountsOutScaled18,
                balancesScaled18,
                userData
            );
        }
    }

    /// @inheritdoc IHooks
    function onAfterRemoveLiquidity(
        address router,
        address pool,
        RemoveLiquidityKind kind,
        uint256 bptAmountIn,
        uint256[] memory amountsOutScaled18,
        uint256[] memory amountsOutRaw,
        uint256[] memory balancesScaled18,
        bytes memory userData
    )
        public
        virtual
        override
        onlyWithHookContract
        onlyAuthorizedCaller
        returns (bool success, uint256[] memory hookAdjustedAmountsOutRaw)
    {
        // Forward to the secondary hook, if it's present and implements onAfterRemoveLiquidity.
        return
            _secondaryHookShouldCall(AFTER_REMOVE_LIQUIDITY)
                ? IHooks(_secondaryHookContract).onAfterRemoveLiquidity(
                    router,
                    pool,
                    kind,
                    bptAmountIn,
                    amountsOutScaled18,
                    amountsOutRaw,
                    balancesScaled18,
                    userData
                )
                : (true, amountsOutRaw);
    }

    /// @inheritdoc IHooks
    function onBeforeSwap(
        PoolSwapParams calldata params,
        address pool
    ) public virtual override onlyWithHookContract onlyAuthorizedCaller returns (bool success) {
        // Forward to the secondary hook, if it's present and implements onBeforeSwap.
        return _secondaryHookShouldCall(BEFORE_SWAP) ? IHooks(_secondaryHookContract).onBeforeSwap(params, pool) : true;
    }

    /// @inheritdoc IHooks
    function onAfterSwap(
        AfterSwapParams calldata params
    )
        public
        virtual
        override
        onlyWithHookContract
        onlyAuthorizedCaller
        returns (bool success, uint256 hookAdjustedAmountCalculatedRaw)
    {
        // Forward to the secondary hook, if it's present and implements onAfterSwap.
        return
            _secondaryHookShouldCall(AFTER_SWAP)
                ? IHooks(_secondaryHookContract).onAfterSwap(params)
                : (true, params.amountCalculatedRaw);
    }

    /// @inheritdoc IHooks
    function onComputeDynamicSwapFeePercentage(
        PoolSwapParams calldata params,
        address pool,
        uint256 staticSwapFeePercentage
    )
        public
        view
        virtual
        override
        onlyWithHookContract
        onlyAuthorizedCaller
        returns (bool success, uint256 dynamicSwapFeePercentage)
    {
        // Forward to the secondary hook, if it's present and implements onComputeDynamicSwapFeePercentage.
        return
            _secondaryHookShouldCall(COMPUTE_DYNAMIC_SWAP_FEE)
                ? IHooks(_secondaryHookContract).onComputeDynamicSwapFeePercentage(
                    params,
                    pool,
                    staticSwapFeePercentage
                )
                : (true, staticSwapFeePercentage);
    }

    /*******************************************************************************
                                  Internal Functions
    *******************************************************************************/

    function _isSwapEnabled() internal view returns (bool) {
        return block.timestamp >= _startTime && block.timestamp <= _endTime;
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
