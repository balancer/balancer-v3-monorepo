// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC1271 } from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import { ERC165 } from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IProtocolFeeBurner } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IProtocolFeeBurner.sol";
import { IComposableCow } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IComposableCow.sol";
import {
    ICowConditionalOrder,
    GPv2Order
} from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/ICowConditionalOrder.sol";

import { SingletonAuthentication } from "@balancer-labs/v3-vault/contracts/SingletonAuthentication.sol";

contract CowSwapFeeBurner is ERC165, IERC1271, IProtocolFeeBurner, ICowConditionalOrder, SingletonAuthentication {
    bytes32 internal immutable SELL_KIND = keccak256("sell");
    bytes32 internal immutable TOKEN_BALANCE = keccak256("erc20");

    IComposableCow public immutable composableCow;
    address public immutable vaultRelayer;

    uint256 public orderLifetime;
    uint256 public targetMinAmount;
    bytes32 public appData;

    uint256 public lastOrderIndex;
    mapping(uint256 => GPv2Order) public orders;

    constructor(
        IVault _vault,
        IComposableCow _composableCow,
        address _vaultRelayer,
        uint256 _orderLifetime,
        uint256 _targetMinAmount,
        bytes32 _appData
    ) SingletonAuthentication(_vault) {
        composableCow = _composableCow;
        vaultRelayer = _vaultRelayer;
        orderLifetime = _orderLifetime;
        targetMinAmount = _targetMinAmount;
        appData = _appData;
    }

    /***************************************************************************
                                   Settings
    ***************************************************************************/
    function setOrderLifetime(uint256 _orderLifetime) external authenticate {
        orderLifetime = _orderLifetime;
    }

    function setTargetMinAmount(uint256 _targetMinAmount) external authenticate {
        targetMinAmount = _targetMinAmount;
    }

    function setAppData(bytes32 _appData) external authenticate {
        appData = _appData;
    }

    /***************************************************************************
                            IProtocolFeeBurner
    ***************************************************************************/
    function burn(
        address pool,
        IERC20 feeToken,
        uint256 feeTokenAmount,
        IERC20 targetToken,
        address recipient
    ) external authenticate {
        if (targetToken == feeToken) {
            revert("TODO");
        }

        SafeERC20.safeTransfer(feeToken, address(this), feeTokenAmount);

        composableCow.create(
            ICowConditionalOrder.ConditionalOrderParams({
                handler: ICowConditionalOrder(address(this)),
                salt: bytes32(0),
                staticInput: abi.encode(lastOrderIndex++)
            }),
            true
        );

        feeToken.approve(vaultRelayer, type(uint256).max);

        orders[lastOrderIndex] = GPv2Order({
            sellToken: feeToken,
            buyToken: targetToken,
            receiver: recipient,
            sellAmount: feeTokenAmount,
            buyAmount: targetMinAmount, //TODO: check if this is correct
            validTo: uint32(block.timestamp + orderLifetime),
            appData: appData,
            feeAmount: 0,
            kind: SELL_KIND,
            partiallyFillable: true,
            sellTokenBalance: TOKEN_BALANCE,
            buyTokenBalance: TOKEN_BALANCE
        });
    }

    /***************************************************************************
                        ICowConditionalOrder & ISwapCowGuard
    ***************************************************************************/
    function getTradeableOrder(
        address,
        address,
        bytes32,
        bytes calldata staticInput,
        bytes calldata
    ) public view returns (GPv2Order memory order) {
        uint256 orderIndex = abi.decode(staticInput, (uint256));

        order = orders[orderIndex];
        if (order.sellAmount == 0) {
            revert("TODO");
        }
    }

    function verify(
        address owner,
        address sender,
        bytes32,
        bytes32,
        bytes32,
        bytes calldata staticInput,
        bytes calldata offchainInput,
        GPv2Order calldata _order
    ) external view override {
        uint256 orderIndex = abi.decode(staticInput, (uint256));

        GPv2Order memory savedOrder = getTradeableOrder(owner, sender, ctx, staticInput, offchainInput);

        require(offchainInput.length == 0, "NonZeroOffchainInput"); //TODO: check if this is correct

        if (_order.buyAmount > savedOrder.buyAmount) {
            savedOrder.buyAmount = _order.buyAmount;
        }

        require(keccak256(abi.encode(savedOrder)) == keccak256(abi.encode(_order)), "BadOrder");
    }

    /***************************************************************************
                                    Others
    ***************************************************************************/
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

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return
            interfaceId == type(ICowConditionalOrder).interfaceId ||
            interfaceId == type(IERC1271).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
