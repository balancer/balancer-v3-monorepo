// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { IERC1271 } from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IProtocolFeeSweeper } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IProtocolFeeSweeper.sol";
import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IVersion } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IVersion.sol";
import { IProtocolFeeBurner } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IProtocolFeeBurner.sol";
import { ICowSwapFeeBurner } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/ICowSwapFeeBurner.sol";
import { IProtocolFeeController } from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeeController.sol";
import { IComposableCow } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IComposableCow.sol";
import {
    ICowConditionalOrderGenerator
} from "@balancer-labs/v3-interfaces/contracts/standalone-utils/ICowConditionalOrderGenerator.sol";
import {
    ICowConditionalOrder,
    GPv2Order
} from "@balancer-labs/v3-interfaces/contracts/standalone-utils/ICowConditionalOrder.sol";

import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";

import { ProtocolFeeSweeper } from "../../contracts/ProtocolFeeSweeper.sol";
import { CowSwapFeeBurner } from "../../contracts/CowSwapFeeBurner.sol";

contract CowSwapFeeBurnerTest is BaseVaultTest {
    using SafeERC20 for IERC20;

    bytes32 internal immutable SELL_KIND = keccak256("sell");
    bytes32 internal immutable TOKEN_BALANCE = keccak256("erc20");
    bytes32 immutable APP_DATA_HASH = keccak256("appData");

    uint256 constant TEST_BURN_AMOUNT = 1e18;
    uint256 constant MIN_TARGET_TOKEN_AMOUNT = 1e18;
    uint256 constant ORDER_LIFETIME = 1 days;
    string constant VERSION = "v1";

    uint256 internal orderDeadline;

    IAuthentication internal feeSweeperAuth;

    address internal composableCowMock = address(bytes20(bytes32("composableCowMock")));
    address internal vaultRelayerMock = address(bytes20(bytes32("vaultRelayerMock")));

    ICowSwapFeeBurner internal cowSwapFeeBurner;
    IProtocolFeeSweeper internal feeSweeper;

    function setUp() public override {
        BaseVaultTest.setUp();

        feeSweeper = new ProtocolFeeSweeper(vault, alice);

        orderDeadline = block.timestamp + ORDER_LIFETIME;

        cowSwapFeeBurner = new CowSwapFeeBurner(
            feeSweeper,
            IComposableCow(composableCowMock),
            vaultRelayerMock,
            APP_DATA_HASH,
            admin,
            VERSION
        );

        feeSweeperAuth = IAuthentication(address(feeSweeper));

        authorizer.grantRole(feeSweeperAuth.getActionId(IProtocolFeeSweeper.setFeeRecipient.selector), admin);
        authorizer.grantRole(feeSweeperAuth.getActionId(IProtocolFeeSweeper.setTargetToken.selector), admin);
        authorizer.grantRole(feeSweeperAuth.getActionId(IProtocolFeeSweeper.addProtocolFeeBurner.selector), admin);
        authorizer.grantRole(feeSweeperAuth.getActionId(IProtocolFeeSweeper.sweepProtocolFeesForToken.selector), admin);

        // Allow the fee sweeper to withdraw protocol fees.
        authorizer.grantRole(
            IAuthentication(address(feeController)).getActionId(
                IProtocolFeeController.withdrawProtocolFeesForToken.selector
            ),
            address(feeSweeper)
        );

        vm.prank(alice);
        feeSweeper.addProtocolFeeBurner(cowSwapFeeBurner);

        vm.prank(bob);
        dai.transfer(address(feeSweeper), DEFAULT_AMOUNT);
    }

    function _approveForBurner(IERC20 token, uint256 amount) private {
        // Must transfer before burning.
        vm.prank(address(feeSweeper));
        token.forceApprove(address(cowSwapFeeBurner), amount);
    }

    function testSweepAndBurn() public {
        // Set up the sweeper to be able to burn.
        vm.prank(admin);
        feeSweeper.setTargetToken(usdc);

        uint256 cowSwapFeeBurnerBalanceBefore = dai.balanceOf(address(cowSwapFeeBurner));

        // Put some fees in the Vault.
        vault.manualSetAggregateSwapFeeAmount(pool, dai, DEFAULT_AMOUNT);

        _mockComposableCowCreate(dai);

        vm.expectEmit();
        emit IProtocolFeeBurner.ProtocolFeeBurned(pool, dai, DEFAULT_AMOUNT, usdc, DEFAULT_AMOUNT, alice);

        vm.startPrank(admin);
        feeSweeper.sweepProtocolFeesForToken(pool, dai, DEFAULT_AMOUNT, orderDeadline, cowSwapFeeBurner);

        assertEq(
            dai.balanceOf(address(cowSwapFeeBurner)),
            cowSwapFeeBurnerBalanceBefore + DEFAULT_AMOUNT,
            "cowSwapFeeBurner should have received the fee"
        );

        assertEq(
            dai.allowance(address(cowSwapFeeBurner), vaultRelayerMock),
            DEFAULT_AMOUNT,
            "vaultRelayer should have been approved to transfer the fee"
        );

        GPv2Order memory order = cowSwapFeeBurner.getOrder(dai);
        GPv2Order memory expectedOrder = GPv2Order({
            sellToken: IERC20(address(dai)),
            buyToken: IERC20(address(usdc)),
            receiver: alice,
            sellAmount: DEFAULT_AMOUNT,
            buyAmount: DEFAULT_AMOUNT,
            validTo: uint32(orderDeadline),
            appData: APP_DATA_HASH,
            feeAmount: 0,
            kind: SELL_KIND,
            partiallyFillable: true,
            sellTokenBalance: TOKEN_BALANCE,
            buyTokenBalance: TOKEN_BALANCE
        });

        assertEq(order, expectedOrder, "Order has incorrect values");
    }

    function testBurn() public {
        vm.expectRevert(abi.encodeWithSelector(ICowConditionalOrder.OrderNotValid.selector, "Order does not exist"));
        cowSwapFeeBurner.getOrder(dai);

        _testBurn();
    }

    function testBurnDouble() public {
        vm.expectRevert(abi.encodeWithSelector(ICowConditionalOrder.OrderNotValid.selector, "Order does not exist"));
        cowSwapFeeBurner.getOrder(dai);

        _testBurn();

        uint256 balance = dai.balanceOf(address(cowSwapFeeBurner));
        vm.prank(address(cowSwapFeeBurner));
        IERC20(address(dai)).safeTransfer(alice, balance);

        assertEq(
            uint256(cowSwapFeeBurner.getOrderStatus(dai)),
            uint256(ICowSwapFeeBurner.OrderStatus.Filled),
            "Order status should be Filled"
        );

        _testBurn();
    }

    function testBurnerIfOrdersExist() public {
        vm.expectRevert(abi.encodeWithSelector(ICowConditionalOrder.OrderNotValid.selector, "Order does not exist"));
        cowSwapFeeBurner.getOrder(dai);

        _testBurn();

        _approveForBurner(dai, TEST_BURN_AMOUNT);

        vm.expectRevert(
            abi.encodeWithSelector(
                ICowSwapFeeBurner.OrderHasUnexpectedStatus.selector,
                ICowSwapFeeBurner.OrderStatus.Active
            )
        );
        _burn();
    }

    function _testBurn() internal {
        uint256 cowSwapFeeBurnerBalanceBefore = dai.balanceOf(address(cowSwapFeeBurner));

        _mockComposableCowCreate(dai);
        _approveForBurner(dai, TEST_BURN_AMOUNT);

        vm.expectEmit();
        emit IProtocolFeeBurner.ProtocolFeeBurned(
            address(0),
            dai,
            TEST_BURN_AMOUNT,
            usdc,
            MIN_TARGET_TOKEN_AMOUNT,
            alice
        );

        _burn();

        assertEq(
            dai.balanceOf(address(cowSwapFeeBurner)),
            cowSwapFeeBurnerBalanceBefore + TEST_BURN_AMOUNT,
            "cowSwapFeeBurner should have received the fee"
        );

        assertEq(
            dai.allowance(address(cowSwapFeeBurner), vaultRelayerMock),
            TEST_BURN_AMOUNT,
            "vaultRelayer should have been approved to transfer the fee"
        );

        GPv2Order memory order = cowSwapFeeBurner.getOrder(dai);
        GPv2Order memory expectedOrder = GPv2Order({
            sellToken: IERC20(address(dai)),
            buyToken: IERC20(address(usdc)),
            receiver: alice,
            sellAmount: TEST_BURN_AMOUNT,
            buyAmount: MIN_TARGET_TOKEN_AMOUNT,
            validTo: uint32(orderDeadline),
            appData: APP_DATA_HASH,
            feeAmount: 0,
            kind: SELL_KIND,
            partiallyFillable: true,
            sellTokenBalance: TOKEN_BALANCE,
            buyTokenBalance: TOKEN_BALANCE
        });

        assertEq(order, expectedOrder, "Order has incorrect values");
        assertEq(
            uint256(cowSwapFeeBurner.getOrderStatus(dai)),
            uint256(ICowSwapFeeBurner.OrderStatus.Active),
            "Order status should be Active"
        );
    }

    function testBurnWhenFeeTokenAsTargetToken() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ICowSwapFeeBurner.InvalidOrderParameters.selector,
                "Fee token and target token are the same"
            )
        );

        vm.prank(address(feeSweeper));
        cowSwapFeeBurner.burn(address(0), dai, TEST_BURN_AMOUNT, dai, MIN_TARGET_TOKEN_AMOUNT, alice, orderDeadline);
    }

    function testBurnWithZeroAmount() public {
        vm.expectRevert(
            abi.encodeWithSelector(ICowSwapFeeBurner.InvalidOrderParameters.selector, "Fee token amount is zero")
        );

        vm.prank(address(feeSweeper));
        cowSwapFeeBurner.burn(address(0), dai, 0, usdc, MIN_TARGET_TOKEN_AMOUNT, alice, orderDeadline);
    }

    function testBurnWhenMinAmountOutIsZero() public {
        vm.expectRevert(
            abi.encodeWithSelector(ICowSwapFeeBurner.InvalidOrderParameters.selector, "Min amount out is zero")
        );

        vm.prank(address(feeSweeper));
        cowSwapFeeBurner.burn(address(0), dai, TEST_BURN_AMOUNT, usdc, 0, alice, orderDeadline);
    }

    function testBurnWhenDeadlineLessThanCurrentBlock() public {
        vm.expectRevert(
            abi.encodeWithSelector(ICowSwapFeeBurner.InvalidOrderParameters.selector, "Deadline is in the past")
        );

        vm.prank(address(feeSweeper));
        cowSwapFeeBurner.burn(
            address(0),
            dai,
            TEST_BURN_AMOUNT,
            usdc,
            MIN_TARGET_TOKEN_AMOUNT,
            alice,
            block.timestamp - 1
        );
    }

    function testBurnWithoutPermission() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        cowSwapFeeBurner.burn(address(0), dai, TEST_BURN_AMOUNT, usdc, MIN_TARGET_TOKEN_AMOUNT, alice, orderDeadline);
    }

    function testGetTradeableOrder() public {
        _mockComposableCowCreate(dai);
        _approveForBurner(dai, TEST_BURN_AMOUNT);

        _burn();

        GPv2Order memory order = cowSwapFeeBurner.getTradeableOrder(
            address(0),
            address(0),
            bytes32(0),
            abi.encode(dai),
            bytes("")
        );
        GPv2Order memory expectedOrder = GPv2Order({
            sellToken: IERC20(address(dai)),
            buyToken: IERC20(address(usdc)),
            receiver: alice,
            sellAmount: TEST_BURN_AMOUNT,
            buyAmount: MIN_TARGET_TOKEN_AMOUNT,
            validTo: uint32(orderDeadline),
            appData: APP_DATA_HASH,
            feeAmount: 0,
            kind: SELL_KIND,
            partiallyFillable: true,
            sellTokenBalance: TOKEN_BALANCE,
            buyTokenBalance: TOKEN_BALANCE
        });

        assertEq(order, expectedOrder, "Order have incorrect values");
    }

    function testGetTradeableOrderWhenOrderNonexistent() public {
        vm.expectRevert(abi.encodeWithSelector(ICowConditionalOrder.OrderNotValid.selector, "Order does not exist"));
        cowSwapFeeBurner.getTradeableOrder(address(0), address(0), bytes32(0), abi.encode(dai), bytes(""));
    }

    function testVerify() public {
        _mockComposableCowCreate(dai);
        _approveForBurner(dai, TEST_BURN_AMOUNT);

        _burn();

        GPv2Order memory order = cowSwapFeeBurner.getTradeableOrder(
            address(0),
            address(0),
            bytes32(0),
            abi.encode(dai),
            bytes("")
        );

        cowSwapFeeBurner.verify(
            address(this),
            address(this),
            bytes32(0),
            bytes32(0),
            bytes32(0),
            abi.encode(dai),
            bytes(""),
            order
        );
    }

    function testVerifyWithInvalidOrder() public {
        vm.expectRevert(abi.encodeWithSelector(ICowConditionalOrder.OrderNotValid.selector, "Order does not exist"));
        cowSwapFeeBurner.verify(
            address(this),
            address(this),
            bytes32(0),
            bytes32(0),
            bytes32(0),
            abi.encode(dai),
            bytes(""),
            GPv2Order({
                sellToken: IERC20(address(dai)),
                buyToken: IERC20(address(usdc)),
                receiver: alice,
                sellAmount: TEST_BURN_AMOUNT,
                buyAmount: MIN_TARGET_TOKEN_AMOUNT,
                validTo: uint32(orderDeadline),
                appData: APP_DATA_HASH,
                feeAmount: 0,
                kind: SELL_KIND,
                partiallyFillable: true,
                sellTokenBalance: TOKEN_BALANCE,
                buyTokenBalance: TOKEN_BALANCE
            })
        );
    }

    function testVerifyWhenBuyPriceMoreThanTargetPrice() public {
        _mockComposableCowCreate(dai);
        _approveForBurner(dai, TEST_BURN_AMOUNT);

        _burn();

        GPv2Order memory order = cowSwapFeeBurner.getTradeableOrder(
            address(0),
            address(0),
            bytes32(0),
            abi.encode(dai),
            bytes("")
        );

        // In this case, the buy price is more than the target price. It is good for the burner because it will get more tokens.
        order.buyAmount = order.buyAmount + 1;
        cowSwapFeeBurner.verify(
            address(this),
            address(this),
            bytes32(0),
            bytes32(0),
            bytes32(0),
            abi.encode(dai),
            bytes(""),
            order
        );
    }

    function testVerifyWithDiscreteOrderWithLessBuyAmount() public {
        _mockComposableCowCreate(dai);
        _approveForBurner(dai, TEST_BURN_AMOUNT);

        _burn();

        GPv2Order memory order = cowSwapFeeBurner.getTradeableOrder(
            address(0),
            address(0),
            bytes32(0),
            abi.encode(dai),
            bytes("")
        );

        order.buyAmount = order.buyAmount - 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                ICowSwapFeeBurner.InvalidOrderParameters.selector,
                "Verify order does not match with existing order"
            )
        );
        cowSwapFeeBurner.verify(
            address(this),
            address(this),
            bytes32(0),
            bytes32(0),
            bytes32(0),
            abi.encode(dai),
            bytes(""),
            order
        );
    }

    function testIsValidSignature() public {
        GPv2Order memory order = GPv2Order({
            sellToken: IERC20(address(dai)),
            buyToken: IERC20(address(usdc)),
            receiver: alice,
            sellAmount: TEST_BURN_AMOUNT,
            buyAmount: MIN_TARGET_TOKEN_AMOUNT,
            validTo: uint32(block.timestamp + orderDeadline),
            appData: APP_DATA_HASH,
            feeAmount: 0,
            kind: SELL_KIND,
            partiallyFillable: true,
            sellTokenBalance: TOKEN_BALANCE,
            buyTokenBalance: TOKEN_BALANCE
        });

        IComposableCow.Payload memory payload = IComposableCow.Payload({
            proof: new bytes32[](12),
            params: ICowConditionalOrder.ConditionalOrderParams({
                handler: ICowConditionalOrder(cowSwapFeeBurner),
                salt: bytes32(0),
                staticData: abi.encode(1)
            }),
            offchainInput: abi.encode("offchainInput")
        });

        bytes memory signature = abi.encode(order, payload);

        bytes4 result = IComposableCow.isValidSafeSignature.selector;

        vm.mockCall(
            composableCowMock,
            abi.encodeWithSelector(IComposableCow.domainSeparator.selector),
            abi.encodePacked(keccak256(abi.encode("domainSeparator")))
        );
        vm.mockCall(
            composableCowMock,
            abi.encodeWithSelector(
                IComposableCow.isValidSafeSignature.selector,
                address(cowSwapFeeBurner),
                address(this),
                keccak256(abi.encode("hash")),
                keccak256(abi.encode("domainSeparator")),
                bytes32(0),
                abi.encode(order),
                abi.encode(payload)
            ),
            abi.encode(result)
        );
        assertEq(
            cowSwapFeeBurner.isValidSignature(keccak256(abi.encode("hash")), signature),
            result,
            "isValidSignature should return the result of composableCow.isValidSafeSignature"
        );
    }

    function testSupportsInterface() public {
        assertEq(
            cowSwapFeeBurner.supportsInterface(type(ICowConditionalOrder).interfaceId),
            true,
            "supportsInterface should return true for ICowConditionalOrder"
        );
        assertEq(
            cowSwapFeeBurner.supportsInterface(type(ICowConditionalOrderGenerator).interfaceId),
            true,
            "supportsInterface should return false for ICowConditionalOrderGenerator"
        );
        assertEq(
            cowSwapFeeBurner.supportsInterface(type(IERC1271).interfaceId),
            true,
            "supportsInterface should return true for IERC1271"
        );
        assertEq(
            cowSwapFeeBurner.supportsInterface(type(IERC165).interfaceId),
            true,
            "supportsInterface should return false for IERC165"
        );
        assertEq(
            cowSwapFeeBurner.supportsInterface(type(IERC20).interfaceId),
            false,
            "supportsInterface should return false for IERC20"
        );

        assertEq(
            cowSwapFeeBurner.supportsInterface(0x01ffc9a7), // IERC165.supportsInterface(bytes4)
            true,
            "supportsInterface should return true for the hardcoded selector of ERC165"
        );
        assertEq(
            cowSwapFeeBurner.supportsInterface(0x1626ba7e), // IERC1271.isValidSignature(bytes32,bytes)
            true,
            "supportsInterface should return true for the hardcoded selector of isValidSignature"
        );
        assertEq(
            cowSwapFeeBurner.supportsInterface(0xb8296fc4), // ICowConditionalOrderGenerator.getTradeableOrder(address,address,bytes32,bytes,bytes)
            true,
            "supportsInterface should return true for the hardcoded selector of getTradeableOrder"
        );

        assertEq(
            cowSwapFeeBurner.supportsInterface(0x00000000),
            false,
            "supportsInterface should return false for an unknown interface"
        );

        vm.expectRevert(ICowSwapFeeBurner.InterfaceIsSignatureVerifierMuxer.selector);
        cowSwapFeeBurner.supportsInterface(0x62af8dc2);
    }

    function testRetryOrderIfSenderIsFeeRecipient() public {
        _testRetryOrder(alice);
    }

    function testRetryOrderIfSenderIsOwner() public {
        _testRetryOrder(admin);
    }

    function _testRetryOrder(address sender) internal {
        _mockComposableCowCreate(dai);
        _approveForBurner(dai, TEST_BURN_AMOUNT);

        _burn();

        uint256 halfAmount = TEST_BURN_AMOUNT / 2;

        vm.prank(vaultRelayerMock);
        SafeERC20.safeTransferFrom(dai, address(cowSwapFeeBurner), vaultRelayerMock, halfAmount);
        skip(ORDER_LIFETIME + 1);

        uint256 newOrderDeadline = block.timestamp + ORDER_LIFETIME;
        uint256 newMinAmountOut = MIN_TARGET_TOKEN_AMOUNT + 1;

        _mockComposableCowCreate(dai);
        vm.expectEmit();
        emit ICowSwapFeeBurner.OrderRetried(dai, halfAmount, newMinAmountOut, newOrderDeadline);
        vm.prank(sender);
        cowSwapFeeBurner.retryOrder(dai, newMinAmountOut, newOrderDeadline);

        GPv2Order memory order = cowSwapFeeBurner.getOrder(dai);
        GPv2Order memory expectedOrder = GPv2Order({
            sellToken: IERC20(address(dai)),
            buyToken: IERC20(address(usdc)),
            receiver: alice,
            sellAmount: halfAmount,
            buyAmount: newMinAmountOut,
            validTo: uint32(newOrderDeadline),
            appData: APP_DATA_HASH,
            feeAmount: 0,
            kind: SELL_KIND,
            partiallyFillable: true,
            sellTokenBalance: TOKEN_BALANCE,
            buyTokenBalance: TOKEN_BALANCE
        });

        assertEq(order, expectedOrder, "Order have incorrect values");
    }

    function testRetryOrderWithInvalidOrderStatus() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ICowSwapFeeBurner.OrderHasUnexpectedStatus.selector,
                ICowSwapFeeBurner.OrderStatus.Nonexistent
            )
        );
        vm.prank(alice);
        cowSwapFeeBurner.retryOrder(dai, MIN_TARGET_TOKEN_AMOUNT, orderDeadline);
    }

    function testRetryOrderWithInvalidMinAmountOut() public {
        _approveForBurner(dai, TEST_BURN_AMOUNT);
        _mockComposableCowCreate(dai);
        _burn();

        // Non-zero balance and timeout so that the status will be "Failed".
        vm.prank(alice);
        dai.transfer(address(cowSwapFeeBurner), 1);
        skip(ORDER_LIFETIME + 1);

        vm.expectRevert(
            abi.encodeWithSelector(ICowSwapFeeBurner.InvalidOrderParameters.selector, "Min amount out is zero")
        );
        vm.prank(alice);
        cowSwapFeeBurner.retryOrder(dai, 0, orderDeadline);
    }

    function testRetryOrderWithInvalidDeadline() public {
        _approveForBurner(dai, TEST_BURN_AMOUNT);
        _mockComposableCowCreate(dai);
        _burn();

        // Non-zero balance and timeout so that the status will be "Failed".
        vm.prank(alice);
        dai.transfer(address(cowSwapFeeBurner), 1);
        skip(ORDER_LIFETIME + 1);

        vm.expectRevert(
            abi.encodeWithSelector(ICowSwapFeeBurner.InvalidOrderParameters.selector, "Deadline is in the past")
        );
        vm.prank(alice);
        cowSwapFeeBurner.retryOrder(dai, MIN_TARGET_TOKEN_AMOUNT, block.timestamp - 1);
    }

    function testRetryOrderWithoutPermission() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        cowSwapFeeBurner.retryOrder(dai, MIN_TARGET_TOKEN_AMOUNT, orderDeadline);
    }

    function testCancelOrderIfSenderIsFeeRecipient() public {
        _testCancelOrder(alice);
    }

    function testCancelOrderIfSenderIsOwner() public {
        _testCancelOrder(admin);
    }

    function _testCancelOrder(address sender) internal {
        _mockComposableCowCreate(dai);
        _approveForBurner(dai, TEST_BURN_AMOUNT);
        _burn();

        uint256 halfAmount = TEST_BURN_AMOUNT / 2;

        uint256 balanceBefore = dai.balanceOf(alice);

        vm.prank(vaultRelayerMock);
        SafeERC20.safeTransferFrom(dai, address(cowSwapFeeBurner), vaultRelayerMock, halfAmount);
        skip(ORDER_LIFETIME + 1);

        _mockComposableCowCreate(dai);
        vm.expectEmit();
        emit ICowSwapFeeBurner.OrderCanceled(dai, halfAmount, alice);

        vm.prank(sender);
        cowSwapFeeBurner.cancelOrder(dai, alice);

        assertEq(
            dai.allowance(address(cowSwapFeeBurner), vaultRelayerMock),
            0,
            "vaultRelayer should have been unapproved"
        );

        assertEq(dai.balanceOf(alice), balanceBefore + halfAmount, "alice should have received the tokens");
        assertEq(
            cowSwapFeeBurner.getOrderStatus(dai),
            ICowSwapFeeBurner.OrderStatus.Nonexistent,
            "Order should be removed"
        );

        vm.expectRevert(abi.encodeWithSelector(ICowConditionalOrder.OrderNotValid.selector, "Order does not exist"));
        cowSwapFeeBurner.getOrder(dai);
    }

    function testCancelOrderWithInvalidOrderStatus() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ICowSwapFeeBurner.OrderHasUnexpectedStatus.selector,
                ICowSwapFeeBurner.OrderStatus.Nonexistent
            )
        );
        vm.prank(alice);
        cowSwapFeeBurner.cancelOrder(dai, alice);
    }

    function testCancelOrderWithoutPermission() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        cowSwapFeeBurner.cancelOrder(dai, alice);
    }

    function testEmergencyRevertOrderIfSenderIsFeeRecipient() public {
        _testEmergencyCancelOrder(alice);
    }

    function testEmergencyRevertOrderIfSenderIsOwner() public {
        _testEmergencyCancelOrder(admin);
    }

    function _testEmergencyCancelOrder(address sender) internal {
        _mockComposableCowCreate(dai);
        _approveForBurner(dai, TEST_BURN_AMOUNT);

        _burn();

        uint256 halfAmount = TEST_BURN_AMOUNT / 2;

        uint256 balanceBefore = dai.balanceOf(alice);

        vm.prank(vaultRelayerMock);
        SafeERC20.safeTransferFrom(dai, address(cowSwapFeeBurner), vaultRelayerMock, halfAmount);
        skip(ORDER_LIFETIME + 1);

        _mockComposableCowCreate(dai);
        vm.expectEmit();
        emit ICowSwapFeeBurner.OrderCanceled(dai, halfAmount, alice);
        vm.prank(sender);
        cowSwapFeeBurner.emergencyCancelOrder(dai, alice);

        assertEq(dai.balanceOf(alice), balanceBefore + halfAmount, "alice should have received the tokens");
        assertEq(
            cowSwapFeeBurner.getOrderStatus(dai),
            ICowSwapFeeBurner.OrderStatus.Nonexistent,
            "Order should be removed"
        );

        vm.expectRevert(abi.encodeWithSelector(ICowConditionalOrder.OrderNotValid.selector, "Order does not exist"));
        cowSwapFeeBurner.getOrder(dai);
    }

    function testEmergencyCancelWithoutPermission() public {
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        cowSwapFeeBurner.emergencyCancelOrder(dai, alice);
    }

    function testGetOrderStatus() public {
        _mockComposableCowCreate(dai);
        _approveForBurner(dai, TEST_BURN_AMOUNT);

        _burn();

        assertEq(cowSwapFeeBurner.getOrderStatus(dai), ICowSwapFeeBurner.OrderStatus.Active, "Order should be active");
    }

    function testGetOrderStatusWhenOrderNonexistent() public view {
        assertEq(
            cowSwapFeeBurner.getOrderStatus(dai),
            ICowSwapFeeBurner.OrderStatus.Nonexistent,
            "Order should be active"
        );
    }

    function testGetOrderStatusWhenOrderFailed() public {
        _mockComposableCowCreate(dai);
        _approveForBurner(dai, TEST_BURN_AMOUNT);

        _burn();

        skip(ORDER_LIFETIME + 1);
        assertEq(cowSwapFeeBurner.getOrderStatus(dai), ICowSwapFeeBurner.OrderStatus.Failed, "Order should be failed");
    }

    function testGetOrderStatusWhenOrderFilled() public {
        _mockComposableCowCreate(dai);
        _approveForBurner(dai, TEST_BURN_AMOUNT);

        _burn();

        vm.prank(vaultRelayerMock);
        SafeERC20.safeTransferFrom(dai, address(cowSwapFeeBurner), vaultRelayerMock, TEST_BURN_AMOUNT);

        assertEq(cowSwapFeeBurner.getOrderStatus(dai), ICowSwapFeeBurner.OrderStatus.Filled, "Order should be filled");
    }

    function testVersion() public view {
        assertEq(IVersion(address(cowSwapFeeBurner)).version(), VERSION, "Wrong version");
    }

    function assertEq(GPv2Order memory left, GPv2Order memory right, string memory message) internal pure {
        assertEq(keccak256(abi.encode(left)), keccak256(abi.encode(right)), message);
    }

    function assertEq(
        ICowSwapFeeBurner.OrderStatus left,
        ICowSwapFeeBurner.OrderStatus right,
        string memory message
    ) internal pure {
        assertEq(uint256(left), uint256(right), message);
    }

    function _mockComposableCowCreate(IERC20 sellToken) internal {
        vm.mockCall(
            composableCowMock,
            abi.encodeWithSelector(
                IComposableCow.create.selector,
                ICowConditionalOrder.ConditionalOrderParams({
                    handler: ICowConditionalOrder(cowSwapFeeBurner),
                    salt: bytes32(0),
                    staticData: abi.encode(sellToken)
                }),
                true
            ),
            new bytes(0)
        );
    }

    function _burn() internal {
        vm.prank(address(feeSweeper));
        cowSwapFeeBurner.burn(address(0), dai, TEST_BURN_AMOUNT, usdc, MIN_TARGET_TOKEN_AMOUNT, alice, orderDeadline);
    }
}
