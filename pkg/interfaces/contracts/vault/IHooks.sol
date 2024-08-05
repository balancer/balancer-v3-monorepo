// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

// Explicitly import VaultTypes structs because we expect this interface to be heavily used by external developers.
// Internally, when this list gets too long, we usually just do a simple import to keep things tidy.
import {
    TokenConfig,
    LiquidityManagement,
    PoolSwapParams,
    AfterSwapParams,
    HookFlags,
    AddLiquidityKind,
    RemoveLiquidityKind,
    SwapKind
} from "./VaultTypes.sol";

/**
 * @notice Interface for pool hooks.
 * @dev Hooks are functions invoked by the Vault at specific points in the flow of each operation. This guarantees that
 * they are called in the correct order, and with the correct arguments. To maintain this security, these functions
 * should only be called by the Vault. The recommended way to do this is to derive the hook contract from `BaseHooks`,
 * then use the `onlyVault` modifier from `VaultGuard`. (See the examples in /pool-hooks.)
 */
interface IHooks {
    /***************************************************************************
                                   Register
    ***************************************************************************/

    /**
     * @notice Hook executed when a pool is registered with a non-zero hooks contract.
     * @dev Returns true if registration was successful, and false to revert the pool registration.
     * Make sure this function is properly implemented (e.g. check the factory, and check that the
     * given pool is from the factory). The Vault address will be msg.sender.
     *
     * @param factory Address of the pool factory (contract deploying the pool)
     * @param pool Address of the pool
     * @param tokenConfig An array of descriptors for the tokens the pool will manage
     * @param liquidityManagement Liquidity management flags indicating which functions are enabled
     * @return success True if the hook allowed the registration, false otherwise
     */
    function onRegister(
        address factory,
        address pool,
        TokenConfig[] memory tokenConfig,
        LiquidityManagement calldata liquidityManagement
    ) external returns (bool);

    /**
     * @notice Return the set of hooks implemented by the contract.
     * @dev The Vault will only call hooks the pool says it supports, and of course only if a hooks contract is defined
     * (i.e., the `poolHooksContract` in `PoolRegistrationParams` is non-zero).
     * `onRegister` is the only "mandatory" hook.
     *
     * @return hookFlags Flags indicating which hooks the contract supports
     */
    function getHookFlags() external view returns (HookFlags memory hookFlags);

    /***************************************************************************
                                   Initialize
    ***************************************************************************/

    /**
     * @notice Hook executed before pool initialization.
     * @dev Called if the `shouldCallBeforeInitialize` flag is set in the configuration. Hook contracts should use
     * the `onlyVault` modifier to guarantee this is only called by the Vault.
     *
     * @param exactAmountsIn Exact amounts of input tokens
     * @param userData Optional, arbitrary data sent with the encoded request
     * @return success True if the pool wishes to proceed with initialization
     */
    function onBeforeInitialize(uint256[] memory exactAmountsIn, bytes memory userData) external returns (bool);

    /**
     * @notice Hook to be executed after pool initialization.
     * @dev Called if the `shouldCallAfterInitialize` flag is set in the configuration. Hook contracts should use
     * the `onlyVault` modifier to guarantee this is only called by the Vault.
     *
     * @param exactAmountsIn Exact amounts of input tokens
     * @param bptAmountOut Amount of pool tokens minted during initialization
     * @param userData Optional, arbitrary data sent with the encoded request
     * @return success True if the pool accepts the initialization results
     */
    function onAfterInitialize(
        uint256[] memory exactAmountsIn,
        uint256 bptAmountOut,
        bytes memory userData
    ) external returns (bool);

    /***************************************************************************
                                   Add Liquidity
    ***************************************************************************/

    /**
     * @notice Hook to be executed before adding liquidity.
     * @dev Called if the `shouldCallBeforeAddLiquidity` flag is set in the configuration. Hook contracts should use
     * the `onlyVault` modifier to guarantee this is only called by the Vault.
     *
     * @param router The address (usually a router contract) that initiated a swap operation on the Vault
     * @param pool Pool address, used to fetch pool information from the vault (pool config, tokens, etc.)
     * @param kind The type of add liquidity operation (e.g., proportional, custom)
     * @param maxAmountsInScaled18 Maximum amounts of input tokens
     * @param minBptAmountOut Minimum amount of output pool tokens
     * @param balancesScaled18 Current pool balances, sorted in token registration order
     * @param userData Optional, arbitrary data sent with the encoded request
     * @return success True if the pool wishes to proceed with settlement
     */
    function onBeforeAddLiquidity(
        address router,
        address pool,
        AddLiquidityKind kind,
        uint256[] memory maxAmountsInScaled18,
        uint256 minBptAmountOut,
        uint256[] memory balancesScaled18,
        bytes memory userData
    ) external returns (bool success);

    /**
     * @notice Hook to be executed after adding liquidity.
     * @dev Called if the `shouldCallAfterAddLiquidity` flag is set in the configuration. The Vault will ignore
     * `hookAdjustedAmountsInRaw` unless `enableHookAdjustedAmounts` is true. Hook contracts should use the
     * `onlyVault` modifier to guarantee this is only called by the Vault.
     *
     * @param router The address (usually a router contract) that initiated a swap operation on the Vault
     * @param pool Pool address, used to fetch pool information from the vault (pool config, tokens, etc.)
     * @param kind The type of add liquidity operation (e.g., proportional, custom)
     * @param amountsInScaled18 Actual amounts of tokens added, sorted in token registration order
     * @param amountsInRaw Actual amounts of tokens added, sorted in token registration order
     * @param bptAmountOut Amount of pool tokens minted
     * @param balancesScaled18 Current pool balances, sorted in token registration order
     * @param userData Additional (optional) data provided by the user
     * @return success True if the pool wishes to proceed with settlement
     * @return hookAdjustedAmountsInRaw New amountsInRaw, potentially modified by the hook
     */
    function onAfterAddLiquidity(
        address router,
        address pool,
        AddLiquidityKind kind,
        uint256[] memory amountsInScaled18,
        uint256[] memory amountsInRaw,
        uint256 bptAmountOut,
        uint256[] memory balancesScaled18,
        bytes memory userData
    ) external returns (bool success, uint256[] memory hookAdjustedAmountsInRaw);

    /***************************************************************************
                                 Remove Liquidity
    ***************************************************************************/

    /**
     * @notice Hook to be executed before removing liquidity.
     * @dev Called if the `shouldCallBeforeRemoveLiquidity` flag is set in the configuration. Hook contracts should use
     * the `onlyVault` modifier to guarantee this is only called by the Vault.
     *
     * @param router The address (usually a router contract) that initiated a swap operation on the Vault
     * @param pool Pool address, used to fetch pool information from the vault (pool config, tokens, etc.)
     * @param kind The type of remove liquidity operation (e.g., proportional, custom)
     * @param maxBptAmountIn Maximum amount of input pool tokens
     * @param minAmountsOutScaled18 Minimum output amounts, sorted in token registration order
     * @param balancesScaled18 Current pool balances, sorted in token registration order
     * @param userData Optional, arbitrary data sent with the encoded request
     * @return success True if the pool wishes to proceed with settlement
     */
    function onBeforeRemoveLiquidity(
        address router,
        address pool,
        RemoveLiquidityKind kind,
        uint256 maxBptAmountIn,
        uint256[] memory minAmountsOutScaled18,
        uint256[] memory balancesScaled18,
        bytes memory userData
    ) external returns (bool success);

    /**
     * @notice Hook to be executed after removing liquidity.
     * @dev Called if the `shouldCallAfterRemoveLiquidity` flag is set in the configuration. The Vault will ignore
     * `hookAdjustedAmountsOutRaw` unless `enableHookAdjustedAmounts` is true. Hook contracts should use the
     * `onlyVault` modifier to guarantee this is only called by the Vault.
     *
     * @param router The address (usually a router contract) that initiated a swap operation on the Vault
     * @param pool Pool address, used to fetch pool information from the vault (pool config, tokens, etc.)
     * @param kind The type of remove liquidity operation (e.g., proportional, custom)
     * @param bptAmountIn Amount of pool tokens to burn
     * @param amountsOutScaled18 Scaled amount of tokens to receive, sorted in token registration order
     * @param amountsOutRaw Actual amount of tokens to receive, sorted in token registration order
     * @param balancesScaled18 Current pool balances, sorted in token registration order
     * @param userData Additional (optional) data provided by the user
     * @return success True if the pool wishes to proceed with settlement
     * @return hookAdjustedAmountsOutRaw New amountsOutRaw, potentially modified by the hook
     */
    function onAfterRemoveLiquidity(
        address router,
        address pool,
        RemoveLiquidityKind kind,
        uint256 bptAmountIn,
        uint256[] memory amountsOutScaled18,
        uint256[] memory amountsOutRaw,
        uint256[] memory balancesScaled18,
        bytes memory userData
    ) external returns (bool success, uint256[] memory hookAdjustedAmountsOutRaw);

    /***************************************************************************
                                    Swap
    ***************************************************************************/

    /**
     * @notice Called before a swap to give the Pool an opportunity to perform actions.
     * @dev Called if the `shouldCallBeforeSwap` flag is set in the configuration. Hook contracts should use the
     * `onlyVault` modifier to guarantee this is only called by the Vault.
     *
     * @param params Swap parameters (see PoolSwapParams for struct definition)
     * @param pool Pool address, used to get pool information from the vault (poolData, token config, etc.)
     * @return success True if the pool wishes to proceed with settlement
     */
    function onBeforeSwap(PoolSwapParams calldata params, address pool) external returns (bool success);

    /**
     * @notice Called after a swap to perform further actions once the balances have been updated by the swap.
     * @dev Called if the `shouldCallAfterSwap` flag is set in the configuration. The Vault will ignore
     * `hookAdjustedAmountCalculatedRaw` unless `enableHookAdjustedAmounts` is true. Hook contracts should
     * use the `onlyVault` modifier to guarantee this is only called by the Vault.
     *
     * @param params Swap parameters (see above for struct definition)
     * @return success True if the pool wishes to proceed with settlement
     * @return hookAdjustedAmountCalculatedRaw New amount calculated, potentially modified by the hook
     */
    function onAfterSwap(
        AfterSwapParams calldata params
    ) external returns (bool success, uint256 hookAdjustedAmountCalculatedRaw);

    /**
     * @notice Called after `onBeforeSwap` and before the main swap operation, if the pool has dynamic fees.
     * @dev Called if the `shouldCallComputeDynamicSwapFee` flag is set in the configuration. Hook contracts should use
     * the `onlyVault` modifier to guarantee this is only called by the Vault.
     *
     * @param params Swap parameters (see PoolSwapParams for struct definition)
     * @param pool Pool address, used to get pool information from the vault (poolData, token config, etc.)
     * @param staticSwapFeePercentage 18-decimal FP value of the static swap fee percentage, for reference
     * @return success True if the pool wishes to proceed with settlement
     * @return dynamicSwapFeePercentage Value of the swap fee percentage, as an 18-decimal FP value
     */
    function onComputeDynamicSwapFeePercentage(
        PoolSwapParams calldata params,
        address pool,
        uint256 staticSwapFeePercentage
    ) external view returns (bool success, uint256 dynamicSwapFeePercentage);
}
