// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { SwapKind } from "./VaultTypes.sol";

/// @notice Interface for a Base Pool
interface IBasePool {
    /**
     * @notice Gets the tokens registered to a pool.
     * @dev Delegated to the Vault; added here as a convenience, mainly for off-chain processes.
     * @return tokens List of tokens in the pool
     */
    function getPoolTokens() external view returns (IERC20[] memory tokens);

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
     * @param tokenInIndex The index of the token we're computing the balance for, in token registration order
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
     * @param kind Type of swap (given in or given out)
     * @param pool Address of the liquidity pool
     * @param amountGivenScaled18 Amount given based on kind of the swap (e.g., tokenIn for given in)
     * @param balancesScaled18 Current pool balances
     * @param indexIn Index of tokenIn
     * @param indexOut Index of tokenOut
     * @param sender Originator of the swap transaction
     * @param userData Additional (optional) data required for the swap
     */
    struct SwapParams {
        SwapKind kind;
        uint256 amountGivenScaled18;
        uint256[] balancesScaled18;
        uint256 indexIn;
        uint256 indexOut;
        address sender;
        bytes userData;
    }

    /**
     * @notice Execute a swap in the pool.
     * @param params Swap parameters (see above for struct definition)
     * @return amountCalculatedScaled18 Calculated amount for the swap
     */
    function onSwap(SwapParams calldata params) external returns (uint256 amountCalculatedScaled18);
}
