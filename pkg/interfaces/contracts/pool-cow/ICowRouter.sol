// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { SwapKind } from "../vault/VaultTypes.sol";

interface ICowRouter {
    /**
     * @notice Data for the swap and donate hook.
     * @dev Swap and donate hook is used to swap on CoW AMM pools and donate surplus or fees to the same pool.
     * @param pool Address of the CoW AMM Pool
     * @param sender Account originating the swap and donate operation
     * @param swapKind Type of swap (exact in or exact out)
     * @param swapTokenIn Token to be swapped from
     * @param swapTokenOut Token to be swapped to
     * @param swapMaxAmountIn Exact amount in, when swap is EXACT_IN, or max amount in if swap is EXACT OUT
     * @param swapMinAmountOut Max amount out, when swap is EXACT_IN, or exact amount out if swap is EXACT OUT
     * @param swapDeadline Deadline for the swap, after which it will revert
     * @param donationAmounts Amount of tokens to donate + protocol fees, sorted in token registration order
     * @param userData Additional (optional) data sent with the swap request and emitted with donation and swap events
     */
    struct SwapAndDonateHookParams {
        address pool;
        address sender;
        SwapKind swapKind;
        IERC20 swapTokenIn;
        IERC20 swapTokenOut;
        uint256 swapMaxAmountIn;
        uint256 swapMinAmountOut;
        uint256 swapDeadline;
        uint256[] donationAmounts;
        bytes userData;
    }

    /**
     * @notice Data for the donate hook.
     * @dev Donate hook is used to donate surplus or fees to a CoW AMM pool.
     * @param pool Address of the CoW AMM Pool
     * @param sender Account originating the donate operation
     * @param donationAmounts Amount of tokens to donate + protocol fees, sorted in token registration order
     * @param userData Additional (optional) data sent with the swap request and emitted with the donation event
     */
    struct DonateHookParams {
        address pool;
        address sender;
        uint256[] donationAmounts;
        bytes userData;
    }

    /// @notice The swap transaction was not validated before the specified deadline timestamp.
    error SwapDeadline();

    /**
     * @notice The `newProtocolFeePercentage` is below the minimum limit.
     * @param newProtocolFeePercentage New value of protocol fee percentage
     * @param limit The minimum limit of the protocol fee percentage value
     */
    error ProtocolFeePercentageAboveLimit(uint256 newProtocolFeePercentage, uint256 limit);

    /**
     * @notice A swap and a donation have occurred.
     * @param pool The pool with the tokens being swapped
     * @param swapTokenIn The token entering the Vault (balance increases)
     * @param swapTokenOut The token leaving the Vault (balance decreases)
     * @param swapAmountIn Number of tokenIn tokens
     * @param swapAmountOut Number of tokenOut tokens
     * @param donationAfterFees Amounts donated to the pool after protocol fees, sorted in token registration order
     * @param protocolFeeAmounts Fees collected by the protocol, sorted in token registration order
     * @param userData Additional (optional) data sent with the swap and donate request
     */
    event CoWSwapAndDonation(
        address pool,
        IERC20 swapTokenIn,
        IERC20 swapTokenOut,
        uint256 swapAmountIn,
        uint256 swapAmountOut,
        uint256[] donationAfterFees,
        uint256[] protocolFeeAmounts,
        bytes userData
    );

    /**
     * @notice A donation has occurred.
     * @param pool The pool that receives the donation
     * @param donationAfterFees Amounts donated to the pool after protocol fees, sorted in token registration order
     * @param protocolFeeAmounts Fees collected by the protocol, sorted in token registration order
     * @param userData Additional (optional) data sent with the donate request
     */
    event CoWDonation(address pool, uint256[] donationAfterFees, uint256[] protocolFeeAmounts, bytes userData);

    function swapExactInAndDonateSurplus(
        address pool,
        IERC20 swapTokenIn,
        IERC20 swapTokenOut,
        uint256 swapExactAmountIn,
        uint256 swapMinAmountOut,
        uint256 swapDeadline,
        uint256[] memory donationAmounts,
        bytes memory userData
    ) external returns (uint256 exactAmountOut);

    function swapExactOutAndDonateSurplus(
        address pool,
        IERC20 swapTokenIn,
        IERC20 swapTokenOut,
        uint256 swapMaxAmountIn,
        uint256 swapExactAmountOut,
        uint256 swapDeadline,
        uint256[] memory donationAmounts,
        bytes memory userData
    ) external returns (uint256 exactAmountIn);

    function donate(address pool, uint256[] memory amountsIn, bytes memory userData) external;

    function getProtocolFeePercentage() external view returns (uint256 protocolFeePercentage);

    function getProtocolFees(IERC20 token) external view returns (uint256 fees);

    function setProtocolFeePercentage(uint256 newProtocolFeePercentage) external;
}
