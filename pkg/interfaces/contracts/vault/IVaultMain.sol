// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IAuthorizer } from "./IAuthorizer.sol";
import { IRateProvider } from "./IRateProvider.sol";
import "./VaultTypes.sol";

interface IVaultMain {
    /*******************************************************************************
                              Transient Accounting
    *******************************************************************************/

    /**
     * @notice Invokes a callback on msg.sender with arguments provided in `data`.
     * @dev Callback is `transient`, meaning all balances for the caller have to be settled at the end.
     * @param data Contains function signature and args to be passed to the msg.sender
     * @return result Resulting data from the call
     */
    function invoke(bytes calldata data) external payable returns (bytes memory result);

    /**
     * @notice Settles deltas for a token.
     * @param token Token's address
     * @return paid Amount paid during settlement
     */
    function settle(IERC20 token) external returns (uint256 paid);

    /**
     * @notice Sends tokens to a recipient.
     * @param token Token's address
     * @param to Recipient's address
     * @param amount Amount of tokens to send
     */
    function wire(IERC20 token, address to, uint256 amount) external;

    /**
     * @notice Retrieves tokens from a sender.
     * @dev This function can transfer tokens from users using allowances granted to the Vault.
     * Only trusted routers should be permitted to invoke it. Untrusted routers should use `settle` instead.
     *
     * @param token Token's address
     * @param from Sender's address
     * @param amount Amount of tokens to retrieve
     */
    function retrieve(IERC20 token, address from, uint256 amount) external;

    /***************************************************************************
                                   Add Liquidity
    ***************************************************************************/

    /// @dev Introduce to avoid "stack too deep" - without polluting the Add/RemoveLiquidity params interface.
    struct LiquidityLocals {
        uint256 tokenIndex;
        uint256[] limitsScaled18;
    }

    /**
     * @notice Adds liquidity to a pool.
     * @dev Caution should be exercised when adding liquidity because the Vault has the capability
     * to transfer tokens from any user, given that it holds all allowances.
     *
     * @param params Parameters for the add liquidity (see above for struct definition)
     * @return amountsIn Actual amounts of input tokens
     * @return bptAmountOut Output pool token amount
     * @return returnData Arbitrary (optional) data with encoded response from the pool
     */
    function addLiquidity(
        AddLiquidityParams memory params
    ) external returns (uint256[] memory amountsIn, uint256 bptAmountOut, bytes memory returnData);

    /***************************************************************************
                                 Remove Liquidity
    ***************************************************************************/

    /**
     * @notice Removes liquidity from a pool.
     * @dev Trusted routers can burn pool tokens belonging to any user and require no prior approval from the user.
     * Untrusted routers require prior approval from the user. This is the only function allowed to call
     * _queryModeBalanceIncrease (and only in a query context).
     *
     * @param params Parameters for the remove liquidity (see above for struct definition)
     * @return bptAmountIn Actual amount of BPT burnt
     * @return amountsOut Actual amounts of output tokens
     * @return returnData Arbitrary (optional) data with encoded response from the pool
     */
    function removeLiquidity(
        RemoveLiquidityParams memory params
    ) external returns (uint256 bptAmountIn, uint256[] memory amountsOut, bytes memory returnData);

    /***************************************************************************
                                       Swaps
    ***************************************************************************/

    /**
     * @notice A swap has occurred.
     * @param pool The pool with the tokens being swapped
     * @param tokenIn The token entering the Vault (balance increases)
     * @param tokenOut The token leaving the Vault (balance decreases)
     * @param amountIn Number of tokenIn tokens
     * @param amountOut Number of tokenOut tokens
     * @param swapFeeAmount Swap fee amount paid in token out
     */
    event Swap(
        address indexed pool,
        IERC20 indexed tokenIn,
        IERC20 indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 swapFeeAmount
    );

    /**
     * @notice Swaps tokens based on provided parameters.
     * @dev All parameters are given in raw token decimal encoding.
     * @param params Parameters for the swap (see above for struct definition)
     * @return amountCalculatedRaw Calculated swap amount
     * @return amountInRaw Amount of input tokens for the swap
     * @return amountOutRaw Amount of output tokens from the swap
     */
    function swap(
        SwapParams memory params
    ) external returns (uint256 amountCalculatedRaw, uint256 amountInRaw, uint256 amountOutRaw);

    /*******************************************************************************
                                    Pool Information
    *******************************************************************************/

    /**
     * @notice Gets the index of a token in a given pool.
     * @dev Reverts if the pool is not registered, or if the token does not belong to the pool.
     * @param pool Address of the pool
     * @param token Address of the token
     * @return tokenCount Number of tokens in the pool
     * @return index Index corresponding to the given token in the pool's token list
     */
    function getPoolTokenCountAndIndexOfToken(address pool, IERC20 token) external view returns (uint256, uint256);

    /*******************************************************************************
                                     Miscellaneous
    *******************************************************************************/

    /**
     * @notice Returns the Vault Extension address.
     */
    function getVaultExtension() external view returns (address);
}
