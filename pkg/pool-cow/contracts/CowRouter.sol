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

    // Protocol fee percentage capped at 50%.
    uint256 internal constant _MAX_PROTOCOL_FEE_PERCENTAGE = 50e16;

    // Address that will receive the protocol fees on withdrawal.
    address internal _feeSweeper;
    uint256 internal _protocolFeePercentage;
    // Store the total amount of fees collected in each token.
    mapping(IERC20 token => uint256 feeAmount) internal _collectedProtocolFees;

    constructor(
        IVault vault,
        uint256 protocolFeePercentage,
        address feeSweeper
    ) VaultGuard(vault) SingletonAuthentication(vault) {
        _setProtocolFeePercentage(protocolFeePercentage);
        _setFeeSweeper(feeSweeper);
    }

    /********************************************************
                      Getters and Setters
    ********************************************************/

    /// @inheritdoc ICowRouter
    function getProtocolFeePercentage() external view returns (uint256 protocolFeePercentage) {
        return _protocolFeePercentage;
    }

    function getMaxProtocolFeePercentage() external pure returns (uint256) {
        return _MAX_PROTOCOL_FEE_PERCENTAGE;
    }

    /// @inheritdoc ICowRouter
    function getCollectedProtocolFees(IERC20 token) external view returns (uint256 fees) {
        return _collectedProtocolFees[token];
    }

    /// @inheritdoc ICowRouter
    function getFeeSweeper() external view returns (address feeSweeper) {
        return _feeSweeper;
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

    /// @inheritdoc ICowRouter
    function setFeeSweeper(address newFeeSweeper) external authenticate {
        _setFeeSweeper(newFeeSweeper);
    }

    function _setFeeSweeper(address newFeeSweeper) private {
        if (newFeeSweeper == address(0)) {
            revert InvalidFeeSweeper();
        }
        _feeSweeper = newFeeSweeper;

        emit FeeSweeperChanged(newFeeSweeper);
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
        uint256[] memory transferAmountHints,
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
                        swapAmountGiven: swapExactAmountIn,
                        swapLimit: swapMinAmountOut,
                        swapDeadline: swapDeadline,
                        donationAmounts: donationAmounts,
                        transferAmountHints: transferAmountHints,
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
        uint256[] memory transferAmountHints,
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
                        swapAmountGiven: swapExactAmountOut,
                        swapLimit: swapMaxAmountIn,
                        swapDeadline: swapDeadline,
                        donationAmounts: donationAmounts,
                        transferAmountHints: transferAmountHints,
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
                     Withdraw Protocol Fees
    ********************************************************/

    /// @inheritdoc ICowRouter
    function withdrawCollectedProtocolFees(IERC20 token) external {
        uint256 amountToWithdraw = _collectedProtocolFees[token];
        if (amountToWithdraw > 0) {
            _collectedProtocolFees[token] = 0;
            token.safeTransfer(_feeSweeper, amountToWithdraw);
            emit ProtocolFeesWithdrawn(token, _feeSweeper, amountToWithdraw);
        }
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
            swapAmountIn = swapAndDonateParams.swapAmountGiven;
            (, , swapAmountOut) = _vault.swap(
                VaultSwapParams({
                    kind: SwapKind.EXACT_IN,
                    pool: swapAndDonateParams.pool,
                    tokenIn: swapAndDonateParams.swapTokenIn,
                    tokenOut: swapAndDonateParams.swapTokenOut,
                    amountGivenRaw: swapAndDonateParams.swapAmountGiven,
                    limitRaw: swapAndDonateParams.swapLimit,
                    userData: swapAndDonateParams.userData
                })
            );
        } else {
            swapAmountOut = swapAndDonateParams.swapAmountGiven;
            (, swapAmountIn, ) = _vault.swap(
                VaultSwapParams({
                    kind: SwapKind.EXACT_OUT,
                    pool: swapAndDonateParams.pool,
                    tokenIn: swapAndDonateParams.swapTokenIn,
                    tokenOut: swapAndDonateParams.swapTokenOut,
                    amountGivenRaw: swapAndDonateParams.swapAmountGiven,
                    limitRaw: swapAndDonateParams.swapLimit,
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
            swapAndDonateParams.transferAmountHints,
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
        // This hook assumes that the sender transferred an exact amount of tokens corresponding to
        // `transferAmountHints`, such that `donationAmounts` == `transferAmountHints` and
        // `senderCredits` == 0.
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

        uint256 totalAmountToDonate;

        for (uint256 i = 0; i < amountsToDonate.length; i++) {
            IERC20 token = tokens[i];

            uint256 donationAndFees = amountsToDonate[i];
            uint256 protocolFee = donationAndFees.mulUp(_protocolFeePercentage);
            _collectedProtocolFees[token] += protocolFee;
            protocolFeeAmounts[i] = protocolFee;
            donatedAmounts[i] = donationAndFees - protocolFee;

            totalAmountToDonate += donatedAmounts[i];
        }

        if (totalAmountToDonate > 0) {
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
    }

    /**
     * @notice Checks if upfront transfers were enough to pay for the swap and donation operation and settles.
     * @dev This function uses the concept of available funds (credits) and required funds (debt) to check if the
     * sender transferred enough funds to fulfill the swap and donation. This concept avoids math underflow, since it
     * works only with sums, and allows to revert with the right reason in case the upfront transfer was not enough to
     * cover the operation.
     *
     * @param sender Account originating the swap and donate operation
     * @param tokens Tokens of the pool
     * @param swapTokenIn The token entering the Vault (balance increases)
     * @param swapTokenOut The token leaving the Vault (balance decreases)
     * @param swapAmountIn The amount of tokenIn entering the Vault
     * @param swapAmountOut The amount of tokenOut leaving the Vault
     * @param transferAmountHints Amount of tokens transferred upfront, sorted in token registration order
     * @param donatedAmounts Amount of tokens deposited in the pool as a donation, sorted in token registration order
     * @param feeAmounts Amount of tokens charged as protocol fees by the router, sorted in token registration order
     */
    function _settleSwapAndDonation(
        address sender,
        IERC20[] memory tokens,
        IERC20 swapTokenIn,
        IERC20 swapTokenOut,
        uint256 swapAmountIn,
        uint256 swapAmountOut,
        uint256[] memory transferAmountHints,
        uint256[] memory donatedAmounts,
        uint256[] memory feeAmounts
    ) private {
        // `senderCredits` will contain the number of "leftover" tokens that should be returned to the sender.
        uint256[] memory senderCredits = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            // Credit the sender for tokens received upfront.
            uint256 rawSenderCredits = transferAmountHints[i];
            // Debit the sender for tokens transferred in for the donation and protocol fees, so that they are not
            // returned to the sender.
            uint256 rawSenderDebts = donatedAmounts[i] + feeAmounts[i];

            if (tokens[i] == swapTokenIn) {
                // Debit the sender for tokens charged in the swap operation.
                rawSenderDebts += swapAmountIn;
            } else if (tokens[i] == swapTokenOut) {
                // Credit the sender for tokens received in the swap operation.
                rawSenderCredits += swapAmountOut;
            }

            if (rawSenderCredits < rawSenderDebts) {
                revert InsufficientFunds(tokens[i], rawSenderCredits, rawSenderDebts);
            }

            senderCredits[i] = rawSenderCredits - rawSenderDebts;
        }

        // Transfer tokens from the Vault to the sender and to the router, and settle the vault reserves.
        _settleDonation(sender, tokens, transferAmountHints, feeAmounts, senderCredits);
    }

    function _settleDonation(
        address sender,
        IERC20[] memory tokens,
        uint256[] memory transferAmountHints,
        uint256[] memory routerCredits,
        uint256[] memory senderCredits
    ) private {
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20 token = tokens[i];

            // Tokens sent by the sender to the vault must be settled to generate credits. These credits are spent to
            // pay debts generated by the swap and donation operations, and to pay protocol fees to the router.
            // The proceeds from the swap, along with any leftover tokens, will be returned to the sender.
            uint256 transferAmountHint = transferAmountHints[i];
            if (transferAmountHint > 0) {
                _vault.settle(token, transferAmountHint);
            }

            // Protocol fees are charged on the sender's upfront transfers to the vault, and sent to the router.
            uint256 sendToRouterAmount = routerCredits[i];
            if (sendToRouterAmount > 0) {
                _vault.sendTo(token, address(this), sendToRouterAmount);
            }

            // The swap `amountOut`, and any leftover tokens, are returned to the sender.
            uint256 returnToSenderAmount = senderCredits[i];
            if (returnToSenderAmount > 0) {
                _vault.sendTo(token, sender, returnToSenderAmount);
            }
        }
    }
}
