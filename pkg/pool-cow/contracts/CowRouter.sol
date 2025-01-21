// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

//import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";

import { ICowRouter } from "@balancer-labs/v3-interfaces/contracts/pool-cow/ICowRouter.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { VaultGuard } from "@balancer-labs/v3-vault/contracts/VaultGuard.sol";
import { SingletonAuthentication } from "@balancer-labs/v3-vault/contracts/SingletonAuthentication.sol";

contract CowRouter is SingletonAuthentication, VaultGuard, ICowRouter {
    using FixedPoint for uint256;
    using SafeCast for *;
    //    using SafeERC20 for IERC20;

    // Protocol fee percentage capped at 10%.
    uint256 internal constant MAX_PROTOCOL_FEE_PERCENTAGE = 10e16;

    IPermit2 internal immutable _permit2;

    uint256 internal _protocolFeePercentage;
    mapping(IERC20 => uint256) internal _protocolFees;

    constructor(IVault vault, IPermit2 permit2) VaultGuard(vault) SingletonAuthentication(vault) {
        _permit2 = permit2;
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

    function donate(address pool, uint256[] memory amountsIn, bytes memory userData) external {
        _vault.unlock(
            abi.encodeCall(
                CowRouter.donateHook,
                DonateHookParams({ pool: pool, sender: msg.sender, amountsIn: amountsIn, userData: userData })
            )
        );
    }

    function donateHook(ICowRouter.DonateHookParams memory params) external onlyVault {
        (IERC20[] memory tokens, , , ) = _vault.getPoolTokenInfo(params.pool);
        uint256[] memory donatedSurplus = new uint256[](params.amountsIn.length);
        uint256[] memory feeAmountCollectedByProtocol = new uint256[](params.amountsIn.length);

        for (uint256 i = 0; i < params.amountsIn.length; i++) {
            if (params.amountsIn[i] > 0 && _protocolFeePercentage > 0) {
                uint256 protocolFee = params.amountsIn[i].mulUp(_protocolFeePercentage);
                if (protocolFee > 0) {
                    _permit2.transferFrom(params.sender, address(this), protocolFee.toUint160(), address(tokens[i]));
                    _protocolFees[tokens[i]] += protocolFee;
                    feeAmountCollectedByProtocol[i] = protocolFee;
                    donatedSurplus[i] = params.amountsIn[i] - protocolFee;
                }
            }
        }

        return;
    }

    function getProtocolFeePercentage() external view returns (uint256 protocolFeePercentage) {
        return _protocolFeePercentage;
    }

    function getProtocolFees(IERC20 token) external view returns (uint256 fees) {
        return _protocolFees[token];
    }

    function setProtocolFeePercentage(uint256 newProtocolFeePercentage) external authenticate {
        if (newProtocolFeePercentage > MAX_PROTOCOL_FEE_PERCENTAGE) {
            revert ProtocolFeePercentageAboveLimit(newProtocolFeePercentage, MAX_PROTOCOL_FEE_PERCENTAGE);
        }

        _protocolFeePercentage = newProtocolFeePercentage;
    }
}
