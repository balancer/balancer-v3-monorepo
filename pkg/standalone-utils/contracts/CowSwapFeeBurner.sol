// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC165 } from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import { IERC1271 } from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { ICowSwapFeeBurner } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/ICowSwapFeeBurner.sol";
import { IProtocolFeeBurner } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IProtocolFeeBurner.sol";
import { IComposableCow } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IComposableCow.sol";

import { SingletonAuthentication } from "@balancer-labs/v3-vault/contracts/SingletonAuthentication.sol";
import {
    ICowConditionalOrderGenerator
} from "@balancer-labs/v3-interfaces/contracts/standalone-utils/ICowConditionalOrderGenerator.sol";
import {
    ICowConditionalOrder,
    GPv2Order
} from "@balancer-labs/v3-interfaces/contracts/standalone-utils/ICowConditionalOrder.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

// solhint-disable not-rely-on-time

/**
 * @title CowSwapFeeBurner
 * @notice A contract that burns protocol fees using CowSwap.
 * To make the burner work, it is necessary to run the Cow Watch-Tower (https://github.com/cowprotocol/watch-tower)
 */
contract CowSwapFeeBurner is ICowSwapFeeBurner, ERC165, SingletonAuthentication {
    struct ShortGPv2Order {
        IERC20 buyToken;
        address receiver;
        uint256 buyAmount;
        uint32 validTo;
    }

    bytes4 internal constant _SIGNATURE_VERIFIER_MUXER_INTERFACE = 0x62af8dc2;
    bytes32 internal immutable _sellKind = keccak256("sell");
    bytes32 internal immutable _tokenBalance = keccak256("erc20");

    IComposableCow public immutable composableCow;
    address public immutable vaultRelayer;
    bytes32 public immutable appData;

    mapping(IERC20 => ShortGPv2Order) internal _orders;

    constructor(
        IVault _vault,
        IComposableCow _composableCow,
        address _vaultRelayer,
        bytes32 _appData
    ) SingletonAuthentication(_vault) {
        composableCow = _composableCow;
        vaultRelayer = _vaultRelayer;
        appData = _appData;
    }

    /***************************************************************************
                                ICowSwapFeeBurner
    ***************************************************************************/

    /// @inheritdoc ICowSwapFeeBurner
    function getOrder(IERC20 sellToken) external view returns (GPv2Order memory) {
        return _getOrder(sellToken);
    }

    /// @inheritdoc ICowSwapFeeBurner
    function getOrderStatus(IERC20 sellToken) external view returns (OrderStatus status) {
        (status, ) = _getOrderStatusAndBalance(sellToken);
    }

    /// @inheritdoc ICowSwapFeeBurner
    function retryOrder(IERC20 sellToken, uint256 minTargetTokenAmount, uint256 deadline) external authenticate {
        (OrderStatus status, uint256 amount) = _getOrderStatusAndBalance(sellToken);

        _checkDeadline(deadline);
        _checkMinTargetTokenAmount(minTargetTokenAmount);

        if (status != OrderStatus.Failed) {
            revert OrderHasUnexpectedStatus(status);
        }

        _orders[sellToken].buyAmount = minTargetTokenAmount;
        _orders[sellToken].validTo = uint32(deadline);

        _createCowOrder(sellToken);

        emit OrderRetried(sellToken, amount, minTargetTokenAmount, deadline);
    }

    /// @inheritdoc ICowSwapFeeBurner
    function revertOrder(IERC20 sellToken, address receiver) external authenticate {
        (OrderStatus status, uint256 amount) = _getOrderStatusAndBalance(sellToken);

        if (status != OrderStatus.Failed) {
            revert OrderHasUnexpectedStatus(status);
        }

        delete _orders[sellToken];

        SafeERC20.safeTransfer(sellToken, receiver, amount);

        emit OrderReverted(sellToken, receiver, amount);
    }

    function emergencyRevertOrder(IERC20 sellToken, address receiver) external authenticate {
        delete _orders[sellToken];

        uint256 amount = sellToken.balanceOf(address(this));
        SafeERC20.safeTransfer(sellToken, receiver, amount);

        emit OrderReverted(sellToken, receiver, amount);
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
        uint256 minTargetTokenAmount,
        address recipient,
        uint256 deadline
    ) external authenticate {
        if (targetToken == feeToken) {
            revert InvalidOrderParameters("Fee token and target token are the same");
        } else if (feeTokenAmount == 0) {
            revert InvalidOrderParameters("Fee token amount is zero");
        }

        _checkDeadline(deadline);
        _checkMinTargetTokenAmount(minTargetTokenAmount);

        (OrderStatus status, ) = _getOrderStatusAndBalance(feeToken);
        if (status != OrderStatus.NotExist && status != OrderStatus.Filled) {
            revert OrderHasUnexpectedStatus(status);
        }

        SafeERC20.safeTransferFrom(feeToken, msg.sender, address(this), feeTokenAmount);

        _createCowOrder(feeToken);

        feeToken.approve(vaultRelayer, feeTokenAmount);

        _orders[feeToken] = ShortGPv2Order({
            buyToken: targetToken,
            receiver: recipient,
            buyAmount: minTargetTokenAmount,
            validTo: uint32(deadline)
        });

        emit ProtocolFeeBurned(pool, feeToken, feeTokenAmount, targetToken, minTargetTokenAmount, recipient);
    }

    /***************************************************************************
                            ICowConditionalOrder
    ***************************************************************************/

    /// @inheritdoc ICowConditionalOrderGenerator
    function getTradeableOrder(
        address,
        address,
        bytes32,
        bytes calldata staticInput
    ) public view returns (GPv2Order memory) {
        IERC20 sellToken = IERC20(abi.decode(staticInput, (address)));

        return _getOrder(sellToken);
    }

    /// @inheritdoc ICowConditionalOrder
    function verify(
        address owner,
        address sender,
        bytes32,
        bytes32,
        bytes32 ctx,
        bytes calldata staticInput,
        GPv2Order calldata _order
    ) external view {
        GPv2Order memory savedOrder = getTradeableOrder(owner, sender, ctx, staticInput);

        if (_order.buyAmount > savedOrder.buyAmount) {
            savedOrder.buyAmount = _order.buyAmount;
        }

        if (keccak256(abi.encode(savedOrder)) != keccak256(abi.encode(_order))) {
            revert InvalidOrderParameters("Verify order does not match with existing order");
        }
    }

    /***************************************************************************
                                    Others
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
    function supportsInterface(bytes4 interfaceId) public view override(ERC165, IERC165) returns (bool) {
        // Fails on SignatureVerifierMuxer due to compatibility issues with ComposableCow.
        if (interfaceId == _SIGNATURE_VERIFIER_MUXER_INTERFACE) {
            revert InterfaceIsSignatureVerifierMuxer();
        }

        return
            interfaceId == type(ICowConditionalOrder).interfaceId ||
            interfaceId == type(ICowConditionalOrderGenerator).interfaceId ||
            interfaceId == type(IERC1271).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /***************************************************************************
                                Private Functions
    ***************************************************************************/

    function _getOrder(IERC20 sellToken) private view returns (GPv2Order memory) {
        ShortGPv2Order memory shortOrder = _orders[sellToken];

        if (shortOrder.validTo == 0) {
            revert OrderNotValid("Order does not exist");
        }

        return
            GPv2Order({
                sellToken: sellToken,
                buyToken: shortOrder.buyToken,
                receiver: shortOrder.receiver,
                sellAmount: sellToken.balanceOf(address(this)),
                buyAmount: shortOrder.buyAmount,
                validTo: shortOrder.validTo,
                appData: appData,
                feeAmount: 0,
                kind: _sellKind,
                partiallyFillable: true,
                sellTokenBalance: _tokenBalance,
                buyTokenBalance: _tokenBalance
            });
    }

    function _getOrderStatusAndBalance(IERC20 sellAmount) private view returns (OrderStatus, uint256) {
        ShortGPv2Order storage shortOrder = _orders[sellAmount];

        uint256 deadline = shortOrder.validTo;

        if (deadline == 0) {
            return (OrderStatus.NotExist, 0);
        }

        uint256 balance = sellAmount.balanceOf(address(this));
        if (balance == 0) {
            return (OrderStatus.Filled, balance);
        } else if (deadline >= block.timestamp) {
            return (OrderStatus.Active, balance);
        } else {
            return (OrderStatus.Failed, balance);
        }
    }

    function _checkDeadline(uint256 deadline) private view {
        if (deadline < block.timestamp) {
            revert InvalidOrderParameters("Deadline is in the past");
        }
    }

    function _checkMinTargetTokenAmount(uint256 minTargetTokenAmount) private pure {
        if (minTargetTokenAmount == 0) {
            revert InvalidOrderParameters("Min target token amount is zero");
        }
    }

    function _createCowOrder(IERC20 sellToken) private {
        composableCow.create(
            ICowConditionalOrder.ConditionalOrderParams({
                handler: ICowConditionalOrder(address(this)),
                salt: bytes32(0),
                staticData: abi.encode(sellToken)
            }),
            true
        );
    }
}
