// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC165 } from "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import { IERC1271 } from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { ICowSwapFeeBurner } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/ICowSwapFeeBurner.sol";
import { IProtocolFeeBurner } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IProtocolFeeBurner.sol";
import { IComposableCow } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IComposableCow.sol";
import {
    ICowConditionalOrder,
    GPv2Order
} from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/ICowConditionalOrder.sol";

import { SingletonAuthentication } from "@balancer-labs/v3-vault/contracts/SingletonAuthentication.sol";

contract CowSwapFeeBurner is ICowSwapFeeBurner, ERC165, SingletonAuthentication {
    struct ShortGPv2Order {
        IERC20 sellToken;
        IERC20 buyToken;
        address receiver;
        uint256 sellAmount;
        uint256 buyAmount;
        uint32 validTo;
    }

    bytes32 internal immutable _sellKind = keccak256("sell");
    bytes32 internal immutable _tokenBalance = keccak256("erc20");

    IComposableCow public immutable composableCow;
    address public immutable vaultRelayer;
    bytes32 public immutable appData;

    uint256 public lastOrderIndex;

    mapping(uint256 => ShortGPv2Order) internal _orders;

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
    function getOrder(uint256 orderIndex) external view returns (GPv2Order memory) {
        return _getOrder(orderIndex);
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
            revert TargetTokenIsFeeToken();
        } else if (feeTokenAmount == 0) {
            revert FeeTokenAmountIsZero();
        } else if (minTargetTokenAmount == 0) {
            revert MinTargetTokenAmountIsZero();
        }

        SafeERC20.safeTransferFrom(feeToken, msg.sender, address(this), feeTokenAmount);

        uint256 orderIndex = lastOrderIndex;
        orderIndex++;
        lastOrderIndex = orderIndex;

        composableCow.create(
            ICowConditionalOrder.ConditionalOrderParams({
                handler: ICowConditionalOrder(address(this)),
                salt: bytes32(0),
                staticInput: abi.encode(orderIndex)
            }),
            true
        );

        feeToken.approve(vaultRelayer, type(uint256).max);

        _orders[orderIndex] = ShortGPv2Order({
            sellToken: feeToken,
            buyToken: targetToken,
            receiver: recipient,
            sellAmount: feeTokenAmount,
            buyAmount: minTargetTokenAmount,
            // solhint-disable-next-line not-rely-on-time
            validTo: uint32(block.timestamp + deadline)
        });

        emit ProtocolFeeBurned(pool, feeToken, feeTokenAmount, targetToken, minTargetTokenAmount, recipient);
    }

    /***************************************************************************
                            ICowConditionalOrder
    ***************************************************************************/

    /// @inheritdoc ICowConditionalOrder
    function getTradeableOrder(
        address,
        address,
        bytes32,
        bytes calldata staticInput,
        bytes calldata
    ) public view returns (GPv2Order memory) {
        uint256 orderIndex = abi.decode(staticInput, (uint256));

        return _getOrder(orderIndex);
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

        if (offchainInput.length != 0) {
            revert NonZeroOffchainInput();
        }

        if (_order.buyAmount > savedOrder.buyAmount) {
            savedOrder.buyAmount = _order.buyAmount;
        }

        if (keccak256(abi.encode(savedOrder)) != keccak256(abi.encode(_order))) {
            revert InvalidOrder();
        }
    }

    function _getOrder(uint256 orderIndex) internal view returns (GPv2Order memory) {
        ShortGPv2Order memory shortOrder = _orders[orderIndex];

        if (shortOrder.sellAmount == 0) {
            revert OrderIsNotExist();
        }

        return
            GPv2Order({
                sellToken: shortOrder.sellToken,
                buyToken: shortOrder.buyToken,
                receiver: shortOrder.receiver,
                sellAmount: shortOrder.sellAmount,
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

    /***************************************************************************
                                    Others
    ***************************************************************************/

    /// @inheritdoc IERC1271
    function isValidSignature(bytes32 _hash, bytes memory signature) external view returns (bytes4) {
        (GPv2Order memory order, IComposableCow.PayloadStruct memory payload) = abi.decode(
            signature,
            (GPv2Order, IComposableCow.PayloadStruct)
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
        return
            interfaceId == type(ICowConditionalOrder).interfaceId ||
            interfaceId == type(IERC1271).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
