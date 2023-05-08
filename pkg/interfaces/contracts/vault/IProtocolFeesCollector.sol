// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.7.0 <0.9.0;
pragma experimental ABIEncoderV2;

import "../solidity-utils/openzeppelin/IERC20.sol";

import "./IVault.sol";
import "./IAuthorizer.sol";

interface IProtocolFeesCollector {
    event SwapFeePercentageChanged(uint256 newSwapFeePercentage);

    function withdrawCollectedFees(IERC20[] calldata tokens, uint256[] calldata amounts, address recipient) external;

    function setSwapFeePercentage(uint256 newSwapFeePercentage) external;

    function getSwapFeePercentage() external view returns (uint256);

    function getCollectedFeeAmounts(IERC20[] memory tokens) external view returns (uint256[] memory feeAmounts);

    function getAuthorizer() external view returns (IAuthorizer);

    function vault() external view returns (IVault);
}
