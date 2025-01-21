// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { SwapKind } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

interface ICowRouter {
    struct SwapAndDonateHookParams {
        address pool;
        address sender;
        SwapKind swapKind;
        IERC20 swapTokenIn;
        IERC20 swapTokenOut;
        uint256 swapMaxAmountIn;
        uint256 swapMinAmountOut;
        uint256 swapDeadline;
        uint256[] surplusToDonate;
        bytes userData;
    }

    struct DonateHookParams {
        address pool;
        address sender;
        uint256[] amountsIn;
        bytes userData;
    }

    error ProtocolFeePercentageAboveLimit(uint256 newProtocolFeePercentage, uint256 limit);

    event CoWSwappingAndDonation(
        address pool,
        uint256 amountInSwap,
        IERC20 tokenInSwap,
        uint256 amnountOutSwap,
        IERC20 tokenOutSwap,
        IERC20[] surplusTokens,
        uint256[] donatedSurplus,
        uint256[] feeAmountCollectedByProtocol,
        bytes userData
    );

    event CoWDonation(
        address pool,
        IERC20[] surplusTokens,
        uint256[] donatedSurplus,
        uint256[] feeAmountCollectedByProtocol,
        bytes userData
    );

    function swapExactInAndDonateSurplus(
        address pool,
        IERC20 swapTokenIn,
        IERC20 swapTokenOut,
        uint256 swapExactAmountIn,
        uint256 swapMinAmountOut,
        uint256 swapDeadline,
        uint256[] memory surplusToDonate,
        bytes memory userData
    ) external returns (uint256 exactAmountOut);

    function swapExactOutAndDonateSurplus(
        address pool,
        IERC20 swapTokenIn,
        IERC20 swapTokenOut,
        uint256 swapMaxAmountIn,
        uint256 swapExactAmountOut,
        uint256 swapDeadline,
        uint256[] memory surplusToDonate,
        bytes memory userData
    ) external returns (uint256 exactAmountIn);

    function donate(address pool, uint256[] memory amountsIn, bytes memory userData) external;

    function getProtocolFeePercentage() external view returns (uint256 protocolFeePercentage);

    function getProtocolFees(IERC20 token) external view returns (uint256 fees);

    function setProtocolFeePercentage(uint256 newProtocolFeePercentage) external;
}
