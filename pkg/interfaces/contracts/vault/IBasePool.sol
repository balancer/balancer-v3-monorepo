// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "./IVault.sol";

/// @notice Interface for a Base Pool
interface IBasePool {
    /// @dev The caller is not allowed to execute this function; it should be executed by the Vault only.
    error CallerNotVault();

    /// @dev The pool does not support the given join kind.
    error UnhandledJoinKind();

    /// @dev The pool does not support the given exit kind.
    error UnhandledExitKind();

    /// @dev The pool does not implement a callback it was configured with.
    error CallbackNotImplemented();

    /***************************************************************************
                                  Initialization
    ***************************************************************************/

    /**
     * @notice Initialize pool with seed funds.
     * @dev The vault enforces that this callback will only be called once.
     * @param maxAmountsIn Maximum amounts of tokens to be added
     * @param userData Additional (optional) data provided by the user
     * @return amountsIn Actual amounts of tokens added
     * @return bptAmountOut Amount of BPT tokens minted
     */
    function onInitialize(
        uint256[] memory maxAmountsIn,
        bytes memory userData
    ) external returns (uint256[] memory amountsIn, uint256 bptAmountOut);

    /***************************************************************************
                                   Add Liquidity
    ***************************************************************************/

    enum AddLiquidityKind {
        EXACT_TOKENS_IN_FOR_BPT_OUT,
        TOKEN_IN_FOR_EXACT_BPT_OUT,
        ALL_TOKENS_IN_FOR_EXACT_BPT_OUT
    }

    /**
     * @notice Add liquidity to the pool.
     * @param sender Address of the sender
     * @param balances Current balances of the tokens
     * @param maxAmountsIn Maximum amounts of tokens to be added
     * @param minBptAmountOut Minimum amount of BPT to receive
     * @param kind Add liquidity kind
     * @param userData Additional (optional) data provided by the user
     * @return amountsIn Actual amounts of tokens added
     * @return bptAmountOut Amount of BPT tokens minted
     */
    function onAddLiquidity(
        address sender,
        uint256[] memory balances,
        uint256[] memory maxAmountsIn,
        uint256 minBptAmountOut,
        AddLiquidityKind kind,
        bytes memory userData
    ) external returns (uint256[] memory amountsIn, uint256 bptAmountOut);

    /**
     * @notice Callback after adding liquidity to the pool.
     * @param sender Address of the sender
     * @param currentBalances Current balances of the tokens
     * @param maxAmountsIn Maximum amounts of tokens to be added
     * @param userData Additional (optional) data provided by the user
     * @return success True if the pool wishes to proceed with settlement
     */
    function onAfterAddLiquidity(
        address sender,
        uint256[] memory currentBalances,
        uint256[] memory maxAmountsIn,
        bytes memory userData,
        uint256[] memory amountsIn,
        uint256 bptAmountOut
    ) external returns (bool success);

    /***************************************************************************
                                 Remove Liquidity
    ***************************************************************************/

    enum RemoveLiquidityKind {
        EXACT_BPT_IN_FOR_ONE_TOKEN_OUT,
        EXACT_BPT_IN_FOR_TOKENS_OUT,
        BPT_IN_FOR_EXACT_TOKENS_OUT
    }

    /**
     * @notice Remove liquidity from the pool.
     * @param sender Address of the sender
     * @param balances Current balances of the tokens
     * @param minAmountsOut Minimum amounts of tokens to be removed
     * @param maxBptAmountIn Maximum amount of BPT tokens burnt
     * @param kind Remove liquidity kind
     * @param userData Additional (optional) data provided by the user
     * @return amountsOut Actual amounts of tokens removed
     * @return bptAmountIn Actual amount of BPT burned
     */
    function onRemoveLiquidity(
        address sender,
        uint256[] memory balances,
        uint256[] memory minAmountsOut,
        uint256 maxBptAmountIn,
        RemoveLiquidityKind kind,
        bytes memory userData
    ) external returns (uint256[] memory amountsOut, uint256 bptAmountIn);

    /**
     * @notice Callback after removing liquidity from the pool.
     * @param sender Address of the sender
     * @param currentBalances Current balances of the tokens
     * @param minAmountsOut Minimum amounts of tokens to be removed
     * @param userData Additional (optional) data provided by the user
     * @return success True if the pool wishes to proceed with settlement
     */
    function onAfterRemoveLiquidity(
        address sender,
        uint256[] memory currentBalances,
        uint256[] memory minAmountsOut,
        uint256 bptAmountIn,
        bytes memory userData,
        uint256[] memory amountsOut
    ) external returns (bool success);

    /***************************************************************************
                                       Swaps
    ***************************************************************************/

    /**
     * @dev Data for a swap operation.
     * @param kind Type of swap (given in or given out)
     * @param pool Address of the liquidity pool
     * @param tokenIn Token to be swapped from (entering the Vault)
     * @param tokenOut Token to be swapped to (leaving the Vault)
     * @param amountGiven Amount given based on kind of the swap (e.g., tokenIn for given in)
     * @param balances Current pool balances
     * @param indexIn Index of tokenIn
     * @param indexOut Index of tokenOut
     * @param userData Additional (optional) data required for the swap
     */
    struct SwapParams {
        IVault.SwapKind kind;
        IERC20 tokenIn;
        IERC20 tokenOut;
        uint256 amountGiven;
        uint256[] balances;
        uint256 indexIn;
        uint256 indexOut;
        address sender;
        bytes userData;
    }

    /**
     * @dev Data for the callback after a swap operation.
     * @param kind Type of swap (given in or given out)
     * @param tokenIn Token to be swapped from
     * @param tokenOut Token to be swapped to
     * @param amountIn Amount of tokenIn (entering the Vault)
     * @param amountOut Amount of tokenOut (leaving the Vault)
     * @param tokenInBalance Updated (after swap) balance of tokenIn
     * @param tokenOutBalance Updated (after swap) balance of tokenOut
     * @param sender Account originating the swap operation
     * @param userData Additional (optional) data required for the swap
     */
    struct AfterSwapParams {
        IVault.SwapKind kind;
        IERC20 tokenIn;
        IERC20 tokenOut;
        uint256 amountIn;
        uint256 amountOut;
        uint256 tokenInBalance;
        uint256 tokenOutBalance;
        address sender;
        bytes userData;
    }

    /**
     * @notice Execute a swap in the pool.
     * @param params Swap parameters (see above for struct definition)
     * @return amountCalculated Calculated amount for the swap
     */
    function onSwap(SwapParams calldata params) external returns (uint256 amountCalculated);

    /**
     * @notice Called after a swap to give the Pool an opportunity to perform actions.
     * once the balances have been updated by the swap.
     *
     * @param params Swap parameters (see above for struct definition)
     * @param amountCalculated Token amount calculated by the swap
     * @return success True if the pool wishes to proceed with settlement
     */
    function onAfterSwap(AfterSwapParams calldata params, uint256 amountCalculated) external returns (bool success);
    
    /**
     * @notice Gets pool tokens and their balances.
     * @return tokens List of tokens in the pool
     * @return balances Corresponding balances of the tokens
     */
    function getPoolTokens() external view returns (IERC20[] memory tokens, uint256[] memory balances);
}
