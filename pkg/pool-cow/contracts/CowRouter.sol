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
    uint256 internal constant _MAX_PROTOCOL_FEE_PERCENTAGE = 10e16;

    uint256 internal _protocolFeePercentage;
    // Store the total amount of fees collected in each token.
    mapping(IERC20 token => uint256 feeAmount) internal _protocolFees;

    constructor(IVault vault, uint256 protocolFeePercentage) VaultGuard(vault) SingletonAuthentication(vault) {
        _protocolFeePercentage = protocolFeePercentage;
    }

    /********************************************************
                      Getters and Setters
    ********************************************************/

    /// @inheritdoc ICowRouter
    function getProtocolFeePercentage() external view returns (uint256 protocolFeePercentage) {
        return _protocolFeePercentage;
    }

    /// @inheritdoc ICowRouter
    function getProtocolFees(IERC20 token) external view returns (uint256 fees) {
        return _protocolFees[token];
    }

    /// @inheritdoc ICowRouter
    function setProtocolFeePercentage(uint256 newProtocolFeePercentage) external authenticate {
        if (newProtocolFeePercentage > _MAX_PROTOCOL_FEE_PERCENTAGE) {
            revert ProtocolFeePercentageAboveLimit(newProtocolFeePercentage, _MAX_PROTOCOL_FEE_PERCENTAGE);
        }

        _protocolFeePercentage = newProtocolFeePercentage;

        emit ProtocolFeePercentageChanged(newProtocolFeePercentage);
    }

    /********************************************************
                       Swaps and Donations
    ********************************************************/

    /// @inheritdoc ICowRouter
    function swapExactInAndDonateSurplus(
        address pool,
        IERC20 swapTokenIn,
        IERC20 swapTokenOut,
        uint256 swapExactAmountIn,
        uint256 swapMinAmountOut,
        uint256 swapDeadline,
        uint256[] memory donationAmounts,
        bytes memory userData
    ) external authenticate returns (uint256 exactAmountOut) {
        (, exactAmountOut) = abi.decode(
            _vault.unlock(
                abi.encodeCall(
                    CowRouter.swapAndDonateSurplusHook,
                    SwapAndDonateHookParams({
                        pool: pool,
                        sender: msg.sender,
                        swapKind: SwapKind.EXACT_IN,
                        swapTokenIn: swapTokenIn,
                        swapTokenOut: swapTokenOut,
                        swapMaxAmountIn: swapExactAmountIn,
                        swapMinAmountOut: swapMinAmountOut,
                        swapDeadline: swapDeadline,
                        donationAmounts: donationAmounts,
                        userData: userData
                    })
                )
            ),
            (uint256, uint256)
        );
    }

    /// @inheritdoc ICowRouter
    function swapExactOutAndDonateSurplus(
        address pool,
        IERC20 swapTokenIn,
        IERC20 swapTokenOut,
        uint256 swapMaxAmountIn,
        uint256 swapExactAmountOut,
        uint256 swapDeadline,
        uint256[] memory donationAmounts,
        bytes memory userData
    ) external authenticate returns (uint256 exactAmountIn) {
        (exactAmountIn, ) = abi.decode(
            _vault.unlock(
                abi.encodeCall(
                    CowRouter.swapAndDonateSurplusHook,
                    SwapAndDonateHookParams({
                        pool: pool,
                        sender: msg.sender,
                        swapKind: SwapKind.EXACT_OUT,
                        swapTokenIn: swapTokenIn,
                        swapTokenOut: swapTokenOut,
                        swapMaxAmountIn: swapMaxAmountIn,
                        swapMinAmountOut: swapExactAmountOut,
                        swapDeadline: swapDeadline,
                        donationAmounts: donationAmounts,
                        userData: userData
                    })
                )
            ),
            (uint256, uint256)
        );
    }

    /// @inheritdoc ICowRouter
    function donate(address pool, uint256[] memory donationAmounts, bytes memory userData) external {
        _vault.unlock(
            abi.encodeCall(
                CowRouter.donateHook,
                DonateHookParams({
                    pool: pool,
                    sender: msg.sender,
                    donationAmounts: donationAmounts,
                    userData: userData
                })
            )
        );
    }

    /********************************************************
                              Hooks
    ********************************************************/

    /**
     * @notice Hook for swapping and donating values to a CoW AMM pool.
     * @dev Can only be called by the Vault.
     * @param swapAndDonateParams Swap and donate params (see ICowRouter for struct definition)
     * @return swapAmountIn Exact amount of tokenIn of the swap
     * @return swapAmountOut Exact amount of tokenOut of the swap
     */
    function swapAndDonateSurplusHook(
        ICowRouter.SwapAndDonateHookParams memory swapAndDonateParams
    ) external onlyVault returns (uint256 swapAmountIn, uint256 swapAmountOut) {
        (IERC20[] memory tokens, , , ) = _vault.getPoolTokenInfo(swapAndDonateParams.pool);

        // The deadline is timestamp-based: it should not be relied upon for sub-minute accuracy.
        // solhint-disable-next-line not-rely-on-time
        if (block.timestamp > swapAndDonateParams.swapDeadline) {
            revert SwapDeadline();
        }

        if (swapAndDonateParams.swapKind == SwapKind.EXACT_IN) {
            swapAmountIn = swapAndDonateParams.swapMaxAmountIn;
            (, , swapAmountOut) = _vault.swap(
                VaultSwapParams({
                    kind: SwapKind.EXACT_IN,
                    pool: swapAndDonateParams.pool,
                    tokenIn: swapAndDonateParams.swapTokenIn,
                    tokenOut: swapAndDonateParams.swapTokenOut,
                    amountGivenRaw: swapAndDonateParams.swapMaxAmountIn,
                    limitRaw: swapAndDonateParams.swapMinAmountOut,
                    userData: swapAndDonateParams.userData
                })
            );
        } else {
            swapAmountOut = swapAndDonateParams.swapMinAmountOut;
            (, swapAmountIn, ) = _vault.swap(
                VaultSwapParams({
                    kind: SwapKind.EXACT_OUT,
                    pool: swapAndDonateParams.pool,
                    tokenIn: swapAndDonateParams.swapTokenIn,
                    tokenOut: swapAndDonateParams.swapTokenOut,
                    amountGivenRaw: swapAndDonateParams.swapMinAmountOut,
                    limitRaw: swapAndDonateParams.swapMaxAmountIn,
                    userData: swapAndDonateParams.userData
                })
            );
        }

        (uint256[] memory donatedAmounts, uint256[] memory protocolFeeAmounts) = _donateToPool(
            swapAndDonateParams.pool,
            tokens,
            swapAndDonateParams.donationAmounts,
            swapAndDonateParams.userData
        );

        // The pool amount must be deposited in the vault, and protocol fees must be deposited in the router.
        _settleSwapAndDonation(
            swapAndDonateParams.sender,
            tokens,
            swapAndDonateParams.swapTokenIn,
            swapAndDonateParams.swapTokenOut,
            swapAmountIn,
            swapAmountOut,
            donatedAmounts,
            protocolFeeAmounts
        );

        emit CoWSwapAndDonation(
            swapAndDonateParams.pool,
            swapAndDonateParams.swapTokenIn,
            swapAndDonateParams.swapTokenOut,
            swapAmountIn,
            swapAmountOut,
            donatedAmounts,
            protocolFeeAmounts,
            swapAndDonateParams.userData
        );
    }

    /**
     * @notice Hook for donating values to a CoW AMM pool.
     * @dev Can only be called by the Vault.
     * @param params Donate params (see ICowRouter for struct definition)
     */
    function donateHook(ICowRouter.DonateHookParams memory params) external onlyVault {
        (IERC20[] memory tokens, , , ) = _vault.getPoolTokenInfo(params.pool);

        (uint256[] memory donatedAmounts, uint256[] memory protocolFeeAmounts) = _donateToPool(
            params.pool,
            tokens,
            params.donationAmounts,
            params.userData
        );

        // The donations must be deposited in the vault, and protocol fees must be deposited in the router.
        _settleDonation(
            params.sender,
            tokens,
            donatedAmounts,
            protocolFeeAmounts,
            new uint256[](donatedAmounts.length)
        );

        emit CoWDonation(params.pool, donatedAmounts, protocolFeeAmounts, params.userData);
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

    function _settleSwapAndDonation(
        address sender,
        IERC20[] memory tokens,
        IERC20 swapTokenIn,
        IERC20 swapTokenOut,
        uint256 swapAmountIn,
        uint256 swapAmountOut,
        uint256[] memory donatedAmounts,
        uint256[] memory feeAmounts
    ) private {
        uint256[] memory poolAmounts = new uint256[](donatedAmounts.length);
        uint256[] memory senderAmounts = new uint256[](donatedAmounts.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == swapTokenIn) {
                poolAmounts[i] = donatedAmounts[i] + swapAmountIn;
            } else if (tokens[i] == swapTokenOut) {
                if (donatedAmounts[i] >= swapAmountOut) {
                    poolAmounts[i] = donatedAmounts[i] - swapAmountOut;
                } else {
                    senderAmounts[i] = swapAmountOut - donatedAmounts[i];
                }
            } else {
                poolAmounts[i] = donatedAmounts[i];
            }
        }

        _settleDonation(sender, tokens, poolAmounts, feeAmounts, senderAmounts);
    }

    function _settleDonation(
        address sender,
        IERC20[] memory tokens,
        uint256[] memory poolAmounts,
        uint256[] memory routerAmounts,
        uint256[] memory senderAmounts
    ) private {
        for (uint256 i = 0; i < poolAmounts.length; i++) {
            IERC20 token = tokens[i];

            // Donations are deposited in the vault and go to the pool balance.
            uint256 poolAmount = poolAmounts[i];
            if (poolAmount > 0) {
                token.safeTransferFrom(sender, address(_vault), poolAmount);
                _vault.settle(token, poolAmount);
            }

            // Protocol fees are deposited in the router.
            uint256 routerAmount = routerAmounts[i];
            if (routerAmount > 0) {
                token.safeTransferFrom(sender, address(this), routerAmount);
            }

            // The swap's amount out goes to the sender, except by the part that was donated.
            uint256 senderAmount = senderAmounts[i];
            if (senderAmount > 0) {
                _vault.sendTo(token, sender, senderAmount);
            }
        }
    }
}
