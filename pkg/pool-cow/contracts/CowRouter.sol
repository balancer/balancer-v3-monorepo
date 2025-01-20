// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { ICowRouter } from "@balancer-labs/v3-interfaces/contracts/pool-cow/ICowRouter.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { SingletonAuthentication } from "@balancer-labs/v3-vault/contracts/SingletonAuthentication.sol";

contract CowRouter is SingletonAuthentication, ICowRouter {
    // Protocol fee percentage capped at 10%.
    uint256 internal constant MAX_PROTOCOL_FEE_PERCENTAGE = 10e16;

    uint256 internal _protocolFeePercentage;
    mapping(IERC20 => uint256) internal _protocolFees;

    constructor(IVault vault) SingletonAuthentication(vault) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function swapExactInAndDonateSurplus(
        address pool,
        CowSwapExactInParams memory params,
        uint256[] memory surplusToDonate,
        bytes memory userData
    ) external pure returns (uint256 exactAmountOut) {
        return 0;
    }

    function swapExactOutAndDonateSurplus(
        address pool,
        CowSwapExactOutParams memory params,
        uint256[] memory surplusToDonate,
        bytes memory userData
    ) external pure returns (uint256 exactAmountIn) {
        return 0;
    }

    function donate(address pool, uint256[] memory amountsIn, bytes memory userData) external pure {
        return;
    }

    function getProtocolFeePercentage() external view returns (uint256 protocolFeePercentage) {
        return _protocolFeePercentage;
    }

    function getProtocolFees(IERC20 token) external view returns (uint256 fees) {
        return _protocolFees[token];
    }

    function setProtocolFeePercentage(uint256 newProtocolFeePercentage) external authenticate {
        _protocolFeePercentage = newProtocolFeePercentage;
    }
}
