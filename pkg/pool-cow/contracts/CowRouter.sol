// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { ICowRouter } from "@balancer-labs/v3-interfaces/contracts/pool-cow/ICowRouter.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {
    AddLiquidityKind,
    AddLiquidityParams,
    SwapKind,
    VaultSwapParams
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { VaultGuard } from "@balancer-labs/v3-vault/contracts/VaultGuard.sol";
import { SingletonAuthentication } from "@balancer-labs/v3-vault/contracts/SingletonAuthentication.sol";

contract CowRouter is SingletonAuthentication, VaultGuard, ICowRouter {
    using FixedPoint for uint256;
    using SafeERC20 for IERC20;
    using SafeCast for *;

    // Protocol fee percentage capped at 10%.
    uint256 internal constant MAX_PROTOCOL_FEE_PERCENTAGE = 10e16;

    uint256 internal _protocolFeePercentage;
    mapping(IERC20 => uint256) internal _protocolFees;

    constructor(IVault vault) VaultGuard(vault) SingletonAuthentication(vault) {
        // solhint-disable-previous-line no-empty-blocks
    }

    /********************************************************
                      Getters and Setters
    ********************************************************/

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

    /********************************************************
                       Swaps and Donations
    ********************************************************/

    function swapExactInAndDonateSurplus(
        address pool,
        CowSwapExactInParams memory swapParams,
        uint256[] memory surplusToDonate,
        bytes memory userData
    ) external authenticate returns (uint256 exactAmountOut) {
        return
            abi.decode(
                _vault.unlock(
                    abi.encodeCall(
                        CowRouter.swapExactInAndDonateSurplusHook,
                        SwapExactInAndDonateHookParams({
                            pool: pool,
                            sender: msg.sender,
                            swapParams: swapParams,
                            surplusToDonate: surplusToDonate,
                            userData: userData
                        })
                    )
                ),
                (uint256)
            );
    }

    function swapExactOutAndDonateSurplus(
        address pool,
        CowSwapExactOutParams memory params,
        uint256[] memory surplusToDonate,
        bytes memory userData
    ) external view authenticate returns (uint256 exactAmountIn) {
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

    /********************************************************
                              Hooks
    ********************************************************/
    function swapExactInAndDonateSurplusHook(
        ICowRouter.SwapExactInAndDonateHookParams memory swapAndDonateParams
    ) external onlyVault returns (uint256 exactAmountOut) {
        (IERC20[] memory tokens, , , ) = _vault.getPoolTokenInfo(swapAndDonateParams.pool);

        (, , exactAmountOut) = _vault.swap(
            VaultSwapParams({
                kind: SwapKind.EXACT_IN,
                pool: swapAndDonateParams.pool,
                tokenIn: swapAndDonateParams.swapParams.tokenIn,
                tokenOut: swapAndDonateParams.swapParams.tokenOut,
                amountGivenRaw: swapAndDonateParams.swapParams.exactAmountIn,
                limitRaw: swapAndDonateParams.swapParams.minAmountOut,
                userData: swapAndDonateParams.userData
            })
        );

        (uint256[] memory donatedAmounts, uint256[] memory protocolFeeAmounts) = _donateToPool(
            swapAndDonateParams.pool,
            tokens,
            swapAndDonateParams.surplusToDonate,
            swapAndDonateParams.userData
        );

        uint256[] memory poolAmounts = new uint256[](donatedAmounts.length);
        uint256[] memory senderAmounts = new uint256[](donatedAmounts.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == swapAndDonateParams.swapParams.tokenIn) {
                poolAmounts[i] = donatedAmounts[i] + swapAndDonateParams.swapParams.exactAmountIn;
            } else if (tokens[i] == swapAndDonateParams.swapParams.tokenOut) {
                if (donatedAmounts[i] >= exactAmountOut) {
                    poolAmounts[i] = donatedAmounts[i] - exactAmountOut;
                } else {
                    senderAmounts[i] = exactAmountOut - donatedAmounts[i];
                }
            } else {
                poolAmounts[i] = donatedAmounts[i];
            }
        }

        // The pool amount must be deposited in the vault, and protocol fees must be deposited in the router.
        _settlePoolAndRouter(swapAndDonateParams.sender, tokens, poolAmounts, protocolFeeAmounts, senderAmounts);

        emit CoWSwappingAndDonation(
            swapAndDonateParams.pool,
            swapAndDonateParams.swapParams.exactAmountIn,
            swapAndDonateParams.swapParams.tokenIn,
            exactAmountOut,
            swapAndDonateParams.swapParams.tokenOut,
            tokens,
            donatedAmounts,
            protocolFeeAmounts,
            swapAndDonateParams.userData
        );
    }

    function donateHook(ICowRouter.DonateHookParams memory params) external onlyVault {
        (IERC20[] memory tokens, , , ) = _vault.getPoolTokenInfo(params.pool);

        (uint256[] memory donatedAmounts, uint256[] memory protocolFeeAmounts) = _donateToPool(
            params.pool,
            tokens,
            params.amountsIn,
            params.userData
        );

        // The donations must be deposited in the vault, and protocol fees must be deposited in the router.
        _settlePoolAndRouter(
            params.sender,
            tokens,
            donatedAmounts,
            protocolFeeAmounts,
            new uint256[](donatedAmounts.length)
        );

        emit CoWDonation(params.pool, tokens, donatedAmounts, protocolFeeAmounts, params.userData);
    }

    /********************************************************
                        Private Helpers
    ********************************************************/
    function _donateToPool(
        address pool,
        IERC20[] memory tokens,
        uint256[] memory amountsToDonate,
        bytes memory userData
    ) private returns (uint256[] memory donatedAmounts, uint256[] memory protocolFeeAmounts) {
        donatedAmounts = new uint256[](amountsToDonate.length);
        protocolFeeAmounts = new uint256[](amountsToDonate.length);

        for (uint256 i = 0; i < amountsToDonate.length; i++) {
            IERC20 token = tokens[i];

            uint256 donationAndFees = amountsToDonate[i];
            uint256 protocolFee = donationAndFees.mulUp(_protocolFeePercentage);
            _protocolFees[token] += protocolFee;
            protocolFeeAmounts[i] = protocolFee;
            donatedAmounts[i] = donationAndFees - protocolFee;
        }

        _vault.addLiquidity(
            AddLiquidityParams({
                pool: pool,
                to: address(this), // It's a donation, so no BPT will be transferred.
                maxAmountsIn: donatedAmounts,
                minBptAmountOut: 0,
                kind: AddLiquidityKind.DONATION,
                userData: userData
            })
        );
    }

    function _settlePoolAndRouter(
        address sender,
        IERC20[] memory tokens,
        uint256[] memory poolAmounts,
        uint256[] memory routerAmounts,
        uint256[] memory senderAmounts
    ) private {
        for (uint256 i = 0; i < poolAmounts.length; i++) {
            IERC20 token = tokens[i];

            uint256 poolAmount = poolAmounts[i];
            if (poolAmount > 0) {
                token.safeTransferFrom(sender, address(_vault), poolAmount);
                _vault.settle(token, poolAmount);
            }

            uint256 routerAmount = routerAmounts[i];
            if (routerAmount > 0) {
                token.safeTransferFrom(sender, address(this), routerAmount);
            }

            uint256 userAmount = senderAmounts[i];
            if (userAmount > 0) {
                _vault.sendTo(token, sender, userAmount);
            }
        }
    }
}
