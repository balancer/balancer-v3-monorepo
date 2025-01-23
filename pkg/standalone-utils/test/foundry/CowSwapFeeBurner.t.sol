// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC1271 } from "@openzeppelin/contracts/interfaces/IERC1271.sol";

import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";
import { IComposableCow } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IComposableCow.sol";
import {
    ICowConditionalOrder,
    GPv2Order
} from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/ICowConditionalOrder.sol";
import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { ICowSwapFeeBurner } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/ICowSwapFeeBurner.sol";
import { IProtocolFeeBurner } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IProtocolFeeBurner.sol";

import { CowSwapFeeBurner } from "../../contracts/CowSwapFeeBurner.sol";

contract CowSwapFeeBurnerTest is BaseVaultTest {
    using FixedPoint for uint256;

    bytes32 internal immutable SELL_KIND = keccak256("sell");
    bytes32 internal immutable TOKEN_BALANCE = keccak256("erc20");
    bytes32 immutable APP_DATA_HASH = keccak256("appData");

    uint256 constant DEFAULT_TEST_BURN_AMOUNT = 1e18;
    uint256 constant ORDER_DEADLINE = 1 days;
    uint256 constant TARGET_PRICE = 1e18;

    address composableCowMock = address(bytes20(bytes32("composableCowMock")));
    address vaultRelayerMock = address(bytes20(bytes32("vaultRelayerMock")));

    CowSwapFeeBurner cowSwapFeeBurner;

    function setUp() public override {
        BaseVaultTest.setUp();

        cowSwapFeeBurner = new CowSwapFeeBurner(
            vault,
            IComposableCow(composableCowMock),
            vaultRelayerMock,
            APP_DATA_HASH
        );
    }

    function testBurn() public {
        _grantBurnRoleAndApproveTokens();

        uint256 cowSwapFeeBurnerBalanceBefore = dai.balanceOf(address(cowSwapFeeBurner));
        uint256 lastOrderIndex = cowSwapFeeBurner.lastOrderIndex() + 1;

        vm.expectRevert(ICowSwapFeeBurner.OrderIsNotExist.selector);
        cowSwapFeeBurner.getOrder(lastOrderIndex);

        _mockComposableCowCreate(lastOrderIndex);
        vm.expectEmit();
        emit IProtocolFeeBurner.ProtocolFeeBurned(
            address(0),
            dai,
            DEFAULT_TEST_BURN_AMOUNT,
            usdc,
            DEFAULT_TEST_BURN_AMOUNT.mulDown(TARGET_PRICE),
            ORDER_DEADLINE,
            alice
        );
        _burn();

        assertEq(
            dai.balanceOf(address(cowSwapFeeBurner)),
            cowSwapFeeBurnerBalanceBefore + DEFAULT_TEST_BURN_AMOUNT,
            "cowSwapFeeBurner should have received the fee"
        );

        assertEq(
            dai.allowance(address(cowSwapFeeBurner), vaultRelayerMock),
            MAX_UINT256,
            "vaultRelayer should have been approved to transfer the fee"
        );

        GPv2Order memory order = cowSwapFeeBurner.getOrder(lastOrderIndex);
        GPv2Order memory expectedOrder = GPv2Order({
            sellToken: IERC20(address(dai)),
            buyToken: IERC20(address(usdc)),
            receiver: alice,
            sellAmount: DEFAULT_TEST_BURN_AMOUNT,
            buyAmount: DEFAULT_TEST_BURN_AMOUNT.mulDown(TARGET_PRICE),
            validTo: uint32(block.timestamp + ORDER_DEADLINE),
            appData: APP_DATA_HASH,
            feeAmount: 0,
            kind: SELL_KIND,
            partiallyFillable: true,
            sellTokenBalance: TOKEN_BALANCE,
            buyTokenBalance: TOKEN_BALANCE
        });

        assertEq(order, expectedOrder, "Order have incorrect values");
        assertEq(lastOrderIndex, cowSwapFeeBurner.lastOrderIndex(), "lastOrderIndex should have been updated");
    }

    function testBurnWithFeeTokenAsTargetToken() public {
        authorizer.grantRole(cowSwapFeeBurner.getActionId(CowSwapFeeBurner.burn.selector), address(this));

        vm.expectRevert(ICowSwapFeeBurner.TargetTokenIsFeeToken.selector);
        cowSwapFeeBurner.burn(address(0), dai, DEFAULT_TEST_BURN_AMOUNT, dai, TARGET_PRICE, ORDER_DEADLINE, alice);
    }

    function testBurnWithZeroAmount() public {
        authorizer.grantRole(cowSwapFeeBurner.getActionId(CowSwapFeeBurner.burn.selector), address(this));

        vm.expectRevert(ICowSwapFeeBurner.FeeTokenAmountIsZero.selector);
        cowSwapFeeBurner.burn(address(0), dai, 0, usdc, TARGET_PRICE, ORDER_DEADLINE, alice);
    }

    function testBurnWithZeroPrice() public {
        authorizer.grantRole(cowSwapFeeBurner.getActionId(CowSwapFeeBurner.burn.selector), address(this));

        vm.expectRevert(ICowSwapFeeBurner.PriceIsZero.selector);
        cowSwapFeeBurner.burn(address(0), dai, DEFAULT_TEST_BURN_AMOUNT, usdc, 0, ORDER_DEADLINE, alice);
    }

    function testGetTradeableOrder() public {
        _grantBurnRoleAndApproveTokens();

        uint256 lastOrderIndex = cowSwapFeeBurner.lastOrderIndex() + 1;
        _mockComposableCowCreate(lastOrderIndex);
        _burn();

        GPv2Order memory order = cowSwapFeeBurner.getTradeableOrder(
            address(0),
            address(0),
            bytes32(0),
            abi.encode(lastOrderIndex),
            new bytes(0)
        );
        GPv2Order memory expectedOrder = GPv2Order({
            sellToken: IERC20(address(dai)),
            buyToken: IERC20(address(usdc)),
            receiver: alice,
            sellAmount: DEFAULT_TEST_BURN_AMOUNT,
            buyAmount: DEFAULT_TEST_BURN_AMOUNT.mulDown(TARGET_PRICE),
            validTo: uint32(block.timestamp + ORDER_DEADLINE),
            appData: APP_DATA_HASH,
            feeAmount: 0,
            kind: SELL_KIND,
            partiallyFillable: true,
            sellTokenBalance: TOKEN_BALANCE,
            buyTokenBalance: TOKEN_BALANCE
        });

        assertEq(order, expectedOrder, "Order have incorrect values");
    }

    function testVerify() public {
        _grantBurnRoleAndApproveTokens();

        uint256 lastOrderIndex = cowSwapFeeBurner.lastOrderIndex() + 1;
        _mockComposableCowCreate(lastOrderIndex);
        _burn();

        GPv2Order memory order = cowSwapFeeBurner.getTradeableOrder(
            address(0),
            address(0),
            bytes32(0),
            abi.encode(lastOrderIndex),
            new bytes(0)
        );

        cowSwapFeeBurner.verify(
            address(this),
            address(this),
            bytes32(0),
            bytes32(0),
            bytes32(0),
            abi.encodePacked(lastOrderIndex),
            new bytes(0),
            order
        );
    }

    function testVerifyWhenBuyPriceMoreThanTargetPrice() public {
        _grantBurnRoleAndApproveTokens();

        uint256 lastOrderIndex = cowSwapFeeBurner.lastOrderIndex() + 1;
        _mockComposableCowCreate(lastOrderIndex);
        _burn();

        GPv2Order memory order = cowSwapFeeBurner.getTradeableOrder(
            address(0),
            address(0),
            bytes32(0),
            abi.encode(lastOrderIndex),
            new bytes(0)
        );

        order.buyAmount = order.buyAmount + 1;
        cowSwapFeeBurner.verify(
            address(this),
            address(this),
            bytes32(0),
            bytes32(0),
            bytes32(0),
            abi.encodePacked(lastOrderIndex),
            new bytes(0),
            order
        );
    }

    function testVerifyWithNonZeroOffchainInput() public {
        _grantBurnRoleAndApproveTokens();

        uint256 lastOrderIndex = cowSwapFeeBurner.lastOrderIndex() + 1;
        _mockComposableCowCreate(lastOrderIndex);
        _burn();

        GPv2Order memory order = cowSwapFeeBurner.getTradeableOrder(
            address(0),
            address(0),
            bytes32(0),
            abi.encode(lastOrderIndex),
            new bytes(0)
        );

        vm.expectRevert(ICowSwapFeeBurner.NonZeroOffchainInput.selector);
        cowSwapFeeBurner.verify(
            address(this),
            address(this),
            bytes32(0),
            bytes32(0),
            bytes32(0),
            abi.encodePacked(lastOrderIndex),
            new bytes(1),
            order
        );
    }

    function testVerifyWithIncorrectOrder() public {
        _grantBurnRoleAndApproveTokens();

        uint256 lastOrderIndex = cowSwapFeeBurner.lastOrderIndex() + 1;
        _mockComposableCowCreate(lastOrderIndex);
        _burn();

        GPv2Order memory order = cowSwapFeeBurner.getTradeableOrder(
            address(0),
            address(0),
            bytes32(0),
            abi.encode(lastOrderIndex),
            new bytes(0)
        );

        order.buyAmount = order.buyAmount - 1;
        vm.expectRevert(ICowSwapFeeBurner.InvalidOrder.selector);
        cowSwapFeeBurner.verify(
            address(this),
            address(this),
            bytes32(0),
            bytes32(0),
            bytes32(0),
            abi.encodePacked(lastOrderIndex),
            new bytes(0),
            order
        );
    }

    function testIsValidSignature() public {
        GPv2Order memory order = GPv2Order({
            sellToken: IERC20(address(dai)),
            buyToken: IERC20(address(usdc)),
            receiver: alice,
            sellAmount: DEFAULT_TEST_BURN_AMOUNT,
            buyAmount: DEFAULT_TEST_BURN_AMOUNT.mulDown(TARGET_PRICE),
            validTo: uint32(block.timestamp + ORDER_DEADLINE),
            appData: APP_DATA_HASH,
            feeAmount: 0,
            kind: SELL_KIND,
            partiallyFillable: true,
            sellTokenBalance: TOKEN_BALANCE,
            buyTokenBalance: TOKEN_BALANCE
        });

        IComposableCow.PayloadStruct memory payload = IComposableCow.PayloadStruct({
            proof: new bytes32[](12),
            params: ICowConditionalOrder.ConditionalOrderParams({
                handler: ICowConditionalOrder(cowSwapFeeBurner),
                salt: bytes32(0),
                staticInput: abi.encode(1)
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

    function testSupportsInterface() public view {
        assertEq(
            cowSwapFeeBurner.supportsInterface(type(ICowConditionalOrder).interfaceId),
            true,
            "supportsInterface should return true for ICowConditionalOrder"
        );
        assertEq(
            cowSwapFeeBurner.supportsInterface(type(IERC1271).interfaceId),
            true,
            "supportsInterface should return true for IERC1271"
        );
        assertEq(
            cowSwapFeeBurner.supportsInterface(type(IERC20).interfaceId),
            false,
            "supportsInterface should return false for IERC20"
        );
    }

    function _grantBurnRoleAndApproveTokens() internal {
        authorizer.grantRole(cowSwapFeeBurner.getActionId(CowSwapFeeBurner.burn.selector), alice);

        vm.prank(alice);
        dai.approve(address(cowSwapFeeBurner), DEFAULT_TEST_BURN_AMOUNT);
    }

    function _mockComposableCowCreate(uint256 orderId) internal {
        vm.mockCall(
            composableCowMock,
            abi.encodeWithSelector(
                IComposableCow.create.selector,
                ICowConditionalOrder.ConditionalOrderParams({
                    handler: ICowConditionalOrder(cowSwapFeeBurner),
                    salt: bytes32(0),
                    staticInput: abi.encode(orderId)
                }),
                true
            ),
            new bytes(0)
        );
    }

    function _burn() internal {
        vm.prank(alice);
        cowSwapFeeBurner.burn(address(0), dai, DEFAULT_TEST_BURN_AMOUNT, usdc, TARGET_PRICE, ORDER_DEADLINE, alice);
    }

    function assertEq(GPv2Order memory left, GPv2Order memory right, string memory message) internal pure {
        assertEq(keccak256(abi.encode(left)), keccak256(abi.encode(right)), message);
    }
}
