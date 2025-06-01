// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC1271 } from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IProtocolFeeBurner } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IProtocolFeeBurner.sol";
import { ICowSwapFeeBurner } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/ICowSwapFeeBurner.sol";
import { IProtocolFeeSweeper } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IProtocolFeeSweeper.sol";
import { IComposableCow } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IComposableCow.sol";
import {
    ICowConditionalOrderGenerator
} from "@balancer-labs/v3-interfaces/contracts/standalone-utils/ICowConditionalOrderGenerator.sol";
import {
    ICowConditionalOrder,
    GPv2Order
} from "@balancer-labs/v3-interfaces/contracts/standalone-utils/ICowConditionalOrder.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { Version } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Version.sol";
import {
    ReentrancyGuardTransient
} from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/ReentrancyGuardTransient.sol";
import { SingletonAuthentication } from "@balancer-labs/v3-vault/contracts/SingletonAuthentication.sol";

// solhint-disable not-rely-on-time

/**
 * @title CowSwapFeeBurner
 * @notice A contract that burns protocol fees using CowSwap.
 * @dev The Cow Watchtower (https://github.com/cowprotocol/watch-tower) must be running for the burner to function.
 * Only one order per token is allowed at a time.
 */
contract CowSwapFeeBurner is ICowSwapFeeBurner, Ownable2Step, ReentrancyGuardTransient, Version {
    using SafeERC20 for IERC20;

    struct ShortOrder {
        OrderStatus status;
        IERC20 tokenOut;
        address receiver;
        uint256 minAmountOut;
        uint32 deadline;
    }

    bytes4 internal constant _SIGNATURE_VERIFIER_MUXER_INTERFACE = 0x62af8dc2;
    bytes32 internal immutable _sellKind = keccak256("sell");
    bytes32 internal immutable _tokenBalance = keccak256("erc20");

    IComposableCow public immutable composableCow;
    IProtocolFeeSweeper public immutable protocolFeeSweeper;
    address public immutable vaultRelayer;
    bytes32 public immutable appData;

    // Orders are identified by the tokenIn (often called the tokenIn).
    mapping(IERC20 token => ShortOrder order) internal _orders;

    modifier onlyFeeRecipientOrOwner() {
        if (msg.sender != protocolFeeSweeper.getFeeRecipient() && msg.sender != owner()) {
            revert SenderNotAllowed();
        }
        _;
    }

    modifier onlyProtocolFeeSweeper() {
        if (msg.sender != address(protocolFeeSweeper)) {
            revert SenderNotAllowed();
        }
        _;
    }

    constructor(
        IProtocolFeeSweeper _protocolFeeSweeper,
        IComposableCow _composableCow,
        address _vaultRelayer,
        bytes32 _appData,
        address _initialOwner,
        string memory _version
    ) Version(_version) Ownable(_initialOwner) {
        if (address(_protocolFeeSweeper) == address(0)) {
            revert InvalidProtocolFeeSweeper();
        }

        composableCow = _composableCow;
        protocolFeeSweeper = _protocolFeeSweeper;
        vaultRelayer = _vaultRelayer;
        appData = _appData;
    }

    /***************************************************************************
                                ICowSwapFeeBurner
    ***************************************************************************/

    /// @inheritdoc ICowSwapFeeBurner
    function getOrder(IERC20 tokenIn) external view returns (GPv2Order memory) {
        return _getOrder(tokenIn);
    }

    /// @inheritdoc ICowSwapFeeBurner
    function getOrderStatus(IERC20 tokenIn) external view returns (OrderStatus) {
        ShortOrder memory order = _orders[tokenIn];

        _refreshOrderStatus(tokenIn, order);

        return order.status;
    }

    /// @inheritdoc ICowSwapFeeBurner
    function retryOrder(IERC20 tokenIn, uint256 minAmountOut, uint256 deadline) external onlyFeeRecipientOrOwner {
        ShortOrder memory order = _orders[tokenIn];

        // We are trying to make a failed order active again.
        _updateOrderStatus(order, OrderStatus.Active);

        _checkMinAmountOut(minAmountOut);
        _checkDeadline(deadline);

        order.minAmountOut = minAmountOut;
        order.deadline = uint32(deadline);
        order.status = OrderStatus.Active;

        _orders[tokenIn] = order;

        uint256 amount = tokenIn.balanceOf(address(this));

        // Refresh approval with current balance just in case.
        if (tokenIn.allowance(address(this), vaultRelayer) < amount) {
            tokenIn.forceApprove(vaultRelayer, amount);
        }

        _createCowOrder(tokenIn);

        emit OrderRetried(tokenIn, amount, minAmountOut, deadline);
    }

    /// @inheritdoc ICowSwapFeeBurner
    function cancelOrder(IERC20 tokenIn, address receiver) external onlyFeeRecipientOrOwner {
        ShortOrder memory order = _orders[tokenIn];

        // Canceling an order deletes the storage, so the status will be Nonexistent.
        // No need to update the storage, as it's about to be deleted.
        _updateOrderStatus(order, OrderStatus.Nonexistent);

        uint256 amount = tokenIn.balanceOf(address(this));

        _cancelOrder(tokenIn, receiver, amount);
    }

    /// @inheritdoc ICowSwapFeeBurner
    function emergencyCancelOrder(IERC20 tokenIn, address receiver) external onlyFeeRecipientOrOwner {
        // Do not check for a valid transition here - always allow.
        _cancelOrder(tokenIn, receiver, tokenIn.balanceOf(address(this)));
    }

    function _cancelOrder(IERC20 tokenIn, address receiver, uint256 amount) internal {
        tokenIn.forceApprove(vaultRelayer, 0);
        delete _orders[tokenIn];

        SafeERC20.safeTransfer(tokenIn, receiver, amount);

        emit OrderCanceled(tokenIn, amount, receiver);
    }

    /***************************************************************************
                                IProtocolFeeBurner
    ***************************************************************************/

    /// @inheritdoc IProtocolFeeBurner
    function burn(
        address pool,
        IERC20 feeToken,
        uint256 exactFeeTokenAmountIn,
        IERC20 targetToken,
        uint256 minTargetTokenAmountOut,
        address recipient,
        uint256 deadline
    ) external virtual onlyProtocolFeeSweeper nonReentrant {
        _burn(
            pool,
            feeToken,
            exactFeeTokenAmountIn,
            targetToken,
            minTargetTokenAmountOut,
            recipient,
            deadline,
            true // pullFeeToken
        );
    }

    function _burn(
        address pool,
        IERC20 feeToken,
        uint256 feeTokenAmount,
        IERC20 targetToken,
        uint256 minTargetTokenAmountOut,
        address recipient,
        uint256 deadline,
        bool pullFeeToken
    ) internal {
        if (targetToken == feeToken) {
            revert InvalidOrderParameters("Fee token and target token are the same");
        } else if (feeTokenAmount == 0) {
            revert InvalidOrderParameters("Fee token amount is zero");
        }

        ShortOrder memory order = _orders[feeToken];

        _checkMinAmountOut(minTargetTokenAmountOut);
        _checkDeadline(deadline);

        if (pullFeeToken) {
            feeToken.safeTransferFrom(msg.sender, address(this), feeTokenAmount);
        }

        // We will create a new order.
        _updateOrderStatus(order, OrderStatus.Active);

        _createCowOrder(feeToken);

        feeToken.forceApprove(vaultRelayer, feeTokenAmount);

        // Set remaining order fields.
        order.tokenOut = targetToken;
        order.receiver = recipient;
        order.minAmountOut = minTargetTokenAmountOut;
        order.deadline = uint32(deadline);

        _orders[feeToken] = order;

        emit ProtocolFeeBurned(pool, feeToken, feeTokenAmount, targetToken, minTargetTokenAmountOut, recipient);
    }

    /***************************************************************************
                                ICowConditionalOrder
    ***************************************************************************/

    /// @inheritdoc ICowConditionalOrderGenerator
    function getTradeableOrder(
        address,
        address,
        bytes32,
        bytes calldata staticInput,
        bytes calldata
    ) public view returns (GPv2Order memory) {
        IERC20 tokenIn = IERC20(abi.decode(staticInput, (address)));

        return _getOrder(tokenIn);
    }

    /// @inheritdoc ICowConditionalOrder
    function verify(
        address owner,
        address sender,
        bytes32,
        bytes32,
        bytes32 ctx,
        bytes calldata staticInput,
        bytes calldata offchainInput,
        GPv2Order calldata _order
    ) external view {
        GPv2Order memory savedOrder = getTradeableOrder(owner, sender, ctx, staticInput, offchainInput);

        if (_order.buyAmount > savedOrder.buyAmount) {
            savedOrder.buyAmount = _order.buyAmount;
        }

        if (keccak256(abi.encode(savedOrder)) != keccak256(abi.encode(_order))) {
            revert InvalidOrderParameters("Verify order does not match with existing order");
        }
    }

    /***************************************************************************
                                    Miscellaneous
    ***************************************************************************/

    /// @inheritdoc IERC1271
    function isValidSignature(bytes32 _hash, bytes memory signature) external view returns (bytes4) {
        (GPv2Order memory order, IComposableCow.Payload memory payload) = abi.decode(
            signature,
            (GPv2Order, IComposableCow.Payload)
        );

        // Forward the query to ComposableCow
        return
            composableCow.isValidSafeSignature(
                address(this),
                msg.sender,
                _hash,
                composableCow.domainSeparator(),
                bytes32(0),
                abi.encode(order),
                abi.encode(payload)
            );
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
        // Fails on SignatureVerifierMuxer due to compatibility issues with ComposableCow.
        if (interfaceId == _SIGNATURE_VERIFIER_MUXER_INTERFACE) {
            revert InterfaceIsSignatureVerifierMuxer();
        }

        return
            interfaceId == type(ICowConditionalOrder).interfaceId ||
            interfaceId == type(ICowConditionalOrderGenerator).interfaceId ||
            interfaceId == type(IERC1271).interfaceId ||
            interfaceId == type(IERC165).interfaceId;
    }

    /***************************************************************************
                                Private Functions
    ***************************************************************************/

    function _getOrder(IERC20 tokenIn) private view returns (GPv2Order memory) {
        ShortOrder memory shortOrder = _orders[tokenIn];

        if (shortOrder.deadline == 0) {
            revert OrderNotValid("Order does not exist");
        }

        return
            GPv2Order({
                sellToken: tokenIn,
                buyToken: shortOrder.tokenOut,
                receiver: shortOrder.receiver,
                sellAmount: tokenIn.balanceOf(address(this)),
                buyAmount: shortOrder.minAmountOut,
                validTo: shortOrder.deadline,
                appData: appData,
                feeAmount: 0,
                kind: _sellKind,
                partiallyFillable: true,
                sellTokenBalance: _tokenBalance,
                buyTokenBalance: _tokenBalance
            });
    }

    // Cow does not provide an interface to query the status directly. We must infer it from the order fields
    // and token balance.
    function _refreshOrderStatus(IERC20 token, ShortOrder memory order) internal view {
        uint256 deadline = order.deadline;

        if (deadline == 0) {
            // No order exists because it was never created.
            order.status = OrderStatus.Nonexistent;
        } else {
            uint256 balance = token.balanceOf(address(this));

            if (balance == 0) {
                // If no tokens remain, we assume the order was fully executed; all tokens are pulled by the relayer
                // when the order is filled.
                order.status = OrderStatus.Filled;
            } else if (block.timestamp > deadline) {
                // If tokens remain and the deadline passed, the order is considered failed.
                order.status = OrderStatus.Failed;
            } else {
                // Otherwise, the order is still active.
                order.status = OrderStatus.Active;
            }
        }
    }

    // Call this when changing the status due to user action (vs. refreshing it from the contract state).
    // This function will set the status in the order to `newStatus`, or revert.
    function _updateOrderStatus(ShortOrder memory order, OrderStatus newStatus) internal pure {
        OrderStatus oldStatus = order.status;

        // Handle degenerate case; should not happen.
        if (oldStatus == newStatus) {
            return;
        }

        bool valid;

        if (
            oldStatus == OrderStatus.Nonexistent || oldStatus == OrderStatus.Filled || oldStatus == OrderStatus.Failed
        ) {
            // If an order doesn't exist, all you can do is create it.
            // If an order was successfully filled, you can create a new order for the same token.
            // If an order failed, you can retry it (making it active again).
            valid = newStatus == OrderStatus.Active;
        }

        if (oldStatus == OrderStatus.Active) {
            // If an order is active, it can be:
            // 1) Filled: indicated by a zero balance)
            // 2) Failed: indicated by a non-zero balance and a timestamp past the deadline
            // 3) Nonexistent: canceling an active order deletes the storage
            valid =
                newStatus == OrderStatus.Filled ||
                newStatus == OrderStatus.Failed ||
                newStatus == OrderStatus.Nonexistent;
        }

        if (valid == false) {
            revert OrderHasUnexpectedStatus(oldStatus);
        }

        order.status = newStatus;
    }

    function _checkDeadline(uint256 deadline) private view {
        if (block.timestamp > deadline) {
            revert InvalidOrderParameters("Deadline is in the past");
        }
    }

    function _checkMinAmountOut(uint256 minAmountOut) private pure {
        if (minAmountOut == 0) {
            revert InvalidOrderParameters("Min amount out is zero");
        }
    }

    function _createCowOrder(IERC20 tokenIn) private {
        composableCow.create(
            ICowConditionalOrder.ConditionalOrderParams({
                handler: ICowConditionalOrder(address(this)),
                salt: bytes32(0),
                staticData: abi.encode(tokenIn)
            }),
            true
        );
    }
}
