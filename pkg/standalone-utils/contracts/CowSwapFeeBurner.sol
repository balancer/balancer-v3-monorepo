// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { IERC1271 } from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IProtocolFeeBurner } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IProtocolFeeBurner.sol";
import { ICowSwapFeeBurner } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/ICowSwapFeeBurner.sol";
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
import { SingletonAuthentication } from "@balancer-labs/v3-vault/contracts/SingletonAuthentication.sol";

// solhint-disable not-rely-on-time

/**
 * @title CowSwapFeeBurner
 * @notice A contract that burns protocol fees using CowSwap.
 * @dev The Cow Watchtower (https://github.com/cowprotocol/watch-tower) must be running for the burner to function.
 * Only one order per token is allowed at a time.
 */
contract CowSwapFeeBurner is ICowSwapFeeBurner, SingletonAuthentication, Version {
    using SafeERC20 for IERC20;

    struct ShortOrder {
        IERC20 tokenOut;
        address receiver;
        uint256 minAmountOut;
        uint32 deadline;
    }

    bytes4 internal constant _SIGNATURE_VERIFIER_MUXER_INTERFACE = 0x62af8dc2;
    bytes32 internal immutable _sellKind = keccak256("sell");
    bytes32 internal immutable _tokenBalance = keccak256("erc20");

    IComposableCow public immutable composableCow;
    address public immutable vaultRelayer;
    bytes32 public immutable appData;

    // Orders are identified by the tokenIn (often called the tokenIn).
    mapping(IERC20 token => ShortOrder order) internal _orders;

    constructor(
        IVault _vault,
        IComposableCow _composableCow,
        address _vaultRelayer,
        bytes32 _appData,
        string memory _version
    ) SingletonAuthentication(_vault) Version(_version) {
        composableCow = _composableCow;
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
    function getOrderStatus(IERC20 tokenIn) external view returns (OrderStatus status) {
        (status, ) = _getOrderStatusAndBalance(tokenIn);
    }

    /// @inheritdoc ICowSwapFeeBurner
    function retryOrder(IERC20 tokenIn, uint256 minAmountOut, uint256 deadline) external authenticate {
        (OrderStatus status, uint256 amount) = _getOrderStatusAndBalance(tokenIn);

        if (status != OrderStatus.Failed) {
            revert OrderHasUnexpectedStatus(status);
        }

        _checkMinAmountOut(minAmountOut);
        _checkDeadline(deadline);

        _orders[tokenIn].minAmountOut = minAmountOut;
        _orders[tokenIn].deadline = uint32(deadline);

        _createCowOrder(tokenIn);

        emit OrderRetried(tokenIn, amount, minAmountOut, deadline);
    }

    /// @inheritdoc ICowSwapFeeBurner
    function cancelOrder(IERC20 tokenIn, address receiver) external authenticate {
        (OrderStatus status, uint256 amount) = _getOrderStatusAndBalance(tokenIn);

        if (status != OrderStatus.Failed) {
            revert OrderHasUnexpectedStatus(status);
        }

        _cancelOrder(tokenIn, receiver, amount);
    }

    /// @inheritdoc ICowSwapFeeBurner
    function emergencyCancelOrder(IERC20 tokenIn, address receiver) external authenticate {
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
        uint256 feeTokenAmount,
        IERC20 targetToken,
        uint256 minAmountOut,
        address recipient,
        uint256 deadline
    ) external authenticate {
        if (targetToken == feeToken) {
            revert InvalidOrderParameters("Fee token and target token are the same");
        } else if (feeTokenAmount == 0) {
            revert InvalidOrderParameters("Fee token amount is zero");
        }

        _checkMinAmountOut(minAmountOut);
        _checkDeadline(deadline);

        (OrderStatus status, ) = _getOrderStatusAndBalance(feeToken);
        if (status != OrderStatus.Nonexistent && status != OrderStatus.Filled) {
            revert OrderHasUnexpectedStatus(status);
        }

        feeToken.safeTransferFrom(msg.sender, address(this), feeTokenAmount);

        _createCowOrder(feeToken);

        feeToken.forceApprove(vaultRelayer, feeTokenAmount);

        _orders[feeToken] = ShortOrder({
            tokenOut: targetToken,
            receiver: recipient,
            minAmountOut: minAmountOut,
            deadline: uint32(deadline)
        });

        emit ProtocolFeeBurned(pool, feeToken, feeTokenAmount, targetToken, minAmountOut, recipient);
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

    function _getOrderStatusAndBalance(IERC20 tokenIn) private view returns (OrderStatus, uint256) {
        ShortOrder storage shortOrder = _orders[tokenIn];

        uint256 deadline = shortOrder.deadline;

        if (deadline == 0) {
            return (OrderStatus.Nonexistent, 0);
        }

        uint256 balance = tokenIn.balanceOf(address(this));
        if (balance == 0) {
            return (OrderStatus.Filled, balance);
        } else if (block.timestamp > deadline) {
            return (OrderStatus.Failed, balance);
        }

        return (OrderStatus.Active, balance);
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
