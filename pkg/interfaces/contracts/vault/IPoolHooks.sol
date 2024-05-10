// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "./IVault.sol";
import { SwapKind, AddLiquidityKind, RemoveLiquidityKind } from "./VaultTypes.sol";
import { IBasePool } from "./IBasePool.sol";

/// @notice Interface for pool hooks
interface IPoolHooks {
    /***************************************************************************
                                   Initialize
    ***************************************************************************/

    /**
     * @notice Optional hook to be executed before pool initialization.
     * @param exactAmountsIn Exact amounts of input tokens
     * @param userData Optional, arbitrary data with the encoded request
     * @return success True if the pool wishes to proceed with initialization
     */
    function onBeforeInitialize(uint256[] memory exactAmountsIn, bytes memory userData) external returns (bool);

    /**
     * @notice Optional hook to be executed after pool initialization.
     * @param exactAmountsIn Exact amounts of input tokens
     * @param bptAmountOut Amount of pool tokens minted during initialization
     * @param userData Optional, arbitrary data with the encoded request
     * @return success True if the pool wishes to proceed with initialization
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
     * @notice Optional hook to be executed before adding liquidity.
     * @param sender Address of the sender
     * @param kind The type of add liquidity operation (e.g., proportional, custom)
     * @param maxAmountsInScaled18 Maximum amounts of input tokens
     * @param minBptAmountOut Minimum amount of output pool tokens
     * @param balancesScaled18 Current pool balances, in the same order as the tokens registered in the pool
     * @param userData Optional, arbitrary data with the encoded request
     * @return success True if the pool wishes to proceed with settlement
     */
    function onBeforeAddLiquidity(
        address sender,
        AddLiquidityKind kind,
        uint256[] memory maxAmountsInScaled18,
        uint256 minBptAmountOut,
        uint256[] memory balancesScaled18,
        bytes memory userData
    ) external returns (bool success);

    /**
     * @notice Optional hook to be executed after adding liquidity.
     * @param sender Address of the sender
     * @param amountsInScaled18 Actual amounts of tokens added, in the same order as the tokens registered in the pool
     * @param bptAmountOut Amount of pool tokens minted
     * @param balancesScaled18 Current pool balances, in the same order as the tokens registered in the pool
     * @param userData Additional (optional) data provided by the user
     * @return success True if the pool wishes to proceed with settlement
     */
    function onAfterAddLiquidity(
        address sender,
        uint256[] memory amountsInScaled18,
        uint256 bptAmountOut,
        uint256[] memory balancesScaled18,
        bytes memory userData
    ) external returns (bool success);

    /***************************************************************************
                                 Remove Liquidity
    ***************************************************************************/

    /**
     * @notice Optional hook to be executed before removing liquidity.
     * @param sender Address of the sender
     * @param kind The type of remove liquidity operation (e.g., proportional, custom)
     * @param maxBptAmountIn Maximum amount of input pool tokens
     * @param minAmountsOutScaled18 Minimum output amounts, in the same order as the tokens registered in the pool
     * @param balancesScaled18 Current pool balances, in the same order as the tokens registered in the pool
     * @param userData Optional, arbitrary data with the encoded request
     * @return success True if the pool wishes to proceed with settlement
     */
    function onBeforeRemoveLiquidity(
        address sender,
        RemoveLiquidityKind kind,
        uint256 maxBptAmountIn,
        uint256[] memory minAmountsOutScaled18,
        uint256[] memory balancesScaled18,
        bytes memory userData
    ) external returns (bool success);

    /**
     * @notice Optional hook to be executed after removing liquidity.
     * @param sender Address of the sender
     * @param bptAmountIn Amount of pool tokens to burn
     * @param amountsOutScaled18 Amount of tokens to receive, in the same order as the tokens registered in the pool
     * @param balancesScaled18 Current pool balances, in the same order as the tokens registered in the pool
     * @param userData Additional (optional) data provided by the user
     * @return success True if the pool wishes to proceed with settlement
     */
    function onAfterRemoveLiquidity(
        address sender,
        uint256 bptAmountIn,
        uint256[] memory amountsOutScaled18,
        uint256[] memory balancesScaled18,
        bytes memory userData
    ) external returns (bool success);

    /***************************************************************************
                                    Swap
    ***************************************************************************/

    /**
     * @dev Data for the hook after a swap operation.
     * @param kind Type of swap (exact in or exact out)
     * @param tokenIn Token to be swapped from
     * @param tokenOut Token to be swapped to
     * @param amountInScaled18 Amount of tokenIn (entering the Vault)
     * @param amountOutScaled18 Amount of tokenOut (leaving the Vault)
     * @param tokenInBalanceScaled18 Updated (after swap) balance of tokenIn
     * @param tokenOutBalanceScaled18 Updated (after swap) balance of tokenOut
     * @param sender Account originating the swap operation
     * @param userData Additional (optional) data required for the swap
     */
    struct AfterSwapParams {
        SwapKind kind;
        IERC20 tokenIn;
        IERC20 tokenOut;
        uint256 amountInScaled18;
        uint256 amountOutScaled18;
        uint256 tokenInBalanceScaled18;
        uint256 tokenOutBalanceScaled18;
        address sender;
        bytes userData;
    }

    /**
     * @notice Called before a swap to give the Pool an opportunity to perform actions.
     *
     * @param params Swap parameters (see IBasePool.PoolSwapParams for struct definition)
     * @return success True if the pool wishes to proceed with settlement
     */
    function onBeforeSwap(IBasePool.PoolSwapParams calldata params) external returns (bool success);

    /**
     * @notice Called after a swap to give the Pool an opportunity to perform actions.
     * once the balances have been updated by the swap.
     *
     * @param params Swap parameters (see above for struct definition)
     * @param amountCalculatedScaled18 Token amount calculated by the swap
     * @return success True if the pool wishes to proceed with settlement
     */
    function onAfterSwap(
        AfterSwapParams calldata params,
        uint256 amountCalculatedScaled18
    ) external returns (bool success);

    /**
     * @notice Called before `onBeforeSwap` if the pool has dynamic fees.
     * @param params Swap parameters (see IBasePool.PoolSwapParams for struct definition)
     * @return success True if the pool wishes to proceed with settlement
     * @return dynamicSwapFee Value of the swap fee
     */
    function onComputeDynamicSwapFee(
        IBasePool.PoolSwapParams calldata params
    ) external view returns (bool success, uint256 dynamicSwapFee);
}
