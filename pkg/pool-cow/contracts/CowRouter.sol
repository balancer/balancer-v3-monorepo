// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { ICowRouter } from "@balancer-labs/v3-interfaces/contracts/pool-cow/ICowRouter.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {
    AddLiquidityKind,
    AddLiquidityParams,
    SwapKind,
    VaultSwapParams
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { SingletonAuthentication } from "@balancer-labs/v3-vault/contracts/SingletonAuthentication.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { VaultGuard } from "@balancer-labs/v3-vault/contracts/VaultGuard.sol";

contract CowRouter is SingletonAuthentication, VaultGuard, ICowRouter {
    using FixedPoint for uint256;
    using SafeERC20 for IERC20;
    using SafeCast for *;

    // Protocol fee percentage capped at 10%.
    uint256 internal constant _MAX_PROTOCOL_FEE_PERCENTAGE = 10e16;

    uint256 internal _protocolFeePercentage;
    // Store the total amount of fees collected in each token.
    mapping(IERC20 token => uint256 feeAmount) internal _collectedProtocolFees;

    constructor(IVault vault, uint256 protocolFeePercentage) VaultGuard(vault) SingletonAuthentication(vault) {
        _setProtocolFeePercentage(protocolFeePercentage);
    }

    /********************************************************
                      Getters and Setters
    ********************************************************/

    /// @inheritdoc ICowRouter
    function getProtocolFeePercentage() external view returns (uint256 protocolFeePercentage) {
        return _protocolFeePercentage;
    }

    /// @inheritdoc ICowRouter
    function getCollectedProtocolFees(IERC20 token) external view returns (uint256 fees) {
        return _collectedProtocolFees[token];
    }

    /// @inheritdoc ICowRouter
    function setProtocolFeePercentage(uint256 newProtocolFeePercentage) external authenticate {
        _setProtocolFeePercentage(newProtocolFeePercentage);
    }

    function _setProtocolFeePercentage(uint256 newProtocolFeePercentage) private {
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
        uint256[] memory transferHint,
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
                        transferHint: transferHint,
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
        uint256[] memory transferHint,
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
                        transferHint: transferHint,
                        userData: userData
                    })
                )
            ),
            (uint256, uint256)
        );
    }

    /// @inheritdoc ICowRouter
    function donate(address pool, uint256[] memory donationAmounts, bytes memory userData) external authenticate {
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
     * @notice Hook for swapping and donating to a CoW AMM pool.
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
            swapAndDonateParams.transferHint,
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

        // This hook assumes that transferHint = donationAmounts. It means, the sender transferred the exact amount
        // of tokens to the Vault, no leftovers.
        _settleDonation(
            params.sender,
            tokens,
            params.donationAmounts,
            protocolFeeAmounts,
            new uint256[](params.donationAmounts.length)
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
            _collectedProtocolFees[token] += protocolFee;
            protocolFeeAmounts[i] = protocolFee;
            donatedAmounts[i] = donationAndFees - protocolFee;
        }

        _vault.addLiquidity(
            AddLiquidityParams({
                pool: pool,
                to: address(this), // It's a donation, so no BPT will be transferred
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
        uint256[] memory transferHint,
        uint256[] memory donatedAmounts,
        uint256[] memory feeAmounts
    ) private {
        uint256[] memory senderAmounts = new uint256[](donatedAmounts.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            // The token leftover is the amount transferred from the sender to the Vault (transferHint), minus the
            // amount of tokens donated ton the pool and paid on fees. The leftover should be returned to the sender.
            senderAmounts[i] = transferHint[i] - donatedAmounts[i] - feeAmounts[i];

            if (tokens[i] == swapTokenIn) {
                // The tokenIn amount of the swap is discounted from the leftover that will return to the sender.
                senderAmounts[i] -= swapAmountIn;
            } else if (tokens[i] == swapTokenOut) {
                // The tokenOut amount of the swap is added to the leftover that will return to the sender.
                senderAmounts[i] += swapAmountOut;
            }
        }

        // Transfer tokens from the Vault to the sender and to the router, and settle the vault reserves.
        _settleDonation(sender, tokens, transferHint, feeAmounts, senderAmounts);
    }

    function _settleDonation(
        address sender,
        IERC20[] memory tokens,
        uint256[] memory transferHint,
        uint256[] memory routerAmounts,
        uint256[] memory senderAmounts
    ) private {
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20 token = tokens[i];

            // Tokens sent by the sender to the vault must be settled to generate credit. This credit is spent to pay
            // debts generated by the swap and donation, and to pay protocol fees to the router. Any token leftover and
            // the result of the swap will be returned to the sender.
            uint256 upfrontTransfer = transferHint[i];
            if (upfrontTransfer > 0) {
                _vault.settle(token, upfrontTransfer);
            }

            // Protocol fees are taken from the upfront transfer of the sender to the vault and sent to the router.
            uint256 routerAmount = routerAmounts[i];
            if (routerAmount > 0) {
                _vault.sendTo(token, address(this), routerAmount);
            }

            // Any token leftover and swap amount out are returned to the user.
            uint256 senderAmount = senderAmounts[i];
            if (senderAmount > 0) {
                _vault.sendTo(token, sender, senderAmount);
            }
        }
    }
}
