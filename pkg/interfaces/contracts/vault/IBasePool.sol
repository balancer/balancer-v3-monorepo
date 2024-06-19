// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { ISwapFeePercentageBounds } from "./ISwapFeePercentageBounds.sol";
import { SwapKind } from "./VaultTypes.sol";

/// @notice Interface for a Base Pool
interface IBasePool is ISwapFeePercentageBounds {
    /***************************************************************************
                                   Invariant
    ***************************************************************************/

    /**
     * @notice Computes and returns the pool's invariant.
     * @dev This function computes the invariant based on current balances
     * @param balancesLiveScaled18 Array of current pool balances for each token in the pool, scaled to 18 decimals
     * @return invariant The calculated invariant of the pool, represented as a uint256
     */
    function computeInvariant(uint256[] memory balancesLiveScaled18) external view returns (uint256 invariant);

    /**
     * @dev Computes the new balance of a token after an operation, given the invariant growth ratio and all other
     * balances.
     * @param balancesLiveScaled18 Current live balances (adjusted for decimals, rates, etc.)
     * @param tokenInIndex The index of the token we're computing the balance for, sorted in token registration order
     * @param invariantRatio The ratio of the new invariant (after an operation) to the old
     * @return newBalance The new balance of the selected token, after the operation
     */
    function computeBalance(
        uint256[] memory balancesLiveScaled18,
        uint256 tokenInIndex,
        uint256 invariantRatio
    ) external view returns (uint256 newBalance);

    /***************************************************************************
                                       Swaps
    ***************************************************************************/

    /**
     * @dev Data for a swap operation.
     * @param kind Type of swap (exact in or exact out)
     * @param pool Address of the liquidity pool
     * @param amountGivenScaled18 Amount given based on kind of the swap (e.g., tokenIn for exact in)
     * @param balancesScaled18 Current pool balances
     * @param indexIn Index of tokenIn
     * @param indexOut Index of tokenOut
     * @param user Account originating the swap operation
     * @param router The address (usually a router contract) that initiated a swap operation on the Vault
     * @param userData Additional (optional) data required for the swap
     */
    struct PoolSwapParams {
        SwapKind kind;
        uint256 amountGivenScaled18;
        uint256[] balancesScaled18;
        uint256 indexIn;
        uint256 indexOut;
        address router;
        bytes userData;
    }

    /**
     * @notice Execute a swap in the pool.
     * @param params Swap parameters (see above for struct definition)
     * @return amountCalculatedScaled18 Calculated amount for the swap
     */
    function onSwap(PoolSwapParams calldata params) external returns (uint256 amountCalculatedScaled18);
}
