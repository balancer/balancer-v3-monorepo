// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
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
import { PackedTokenBalance } from "@balancer-labs/v3-solidity-utils/contracts/helpers/PackedTokenBalance.sol";

import { ProtocolFeeSweeper } from "../../contracts/ProtocolFeeSweeper.sol";
import { CowSwapFeeBurner } from "../../contracts/CowSwapFeeBurner.sol";
import { ERC4626CowSwapFeeBurner } from "../../contracts/ERC4626CowSwapFeeBurner.sol";

contract ERC4626CowSwapFeeBurnerTest is BaseVaultTest {
    using SafeERC20 for IERC20;

    bytes32 internal immutable SELL_KIND = keccak256("sell");
    bytes32 internal immutable TOKEN_BALANCE = keccak256("erc20");
    bytes32 immutable APP_DATA_HASH = keccak256("appData");

    uint256 constant TEST_BURN_AMOUNT = 1e18;
    uint256 constant MIN_TARGET_TOKEN_AMOUNT = 1e18;
    uint256 constant ORDER_LIFETIME = 1 days;
    string constant VERSION = "v1";

    uint256 internal orderDeadline;

    IAuthentication internal cowSwapFeeBurnerAuth;
    IAuthentication internal feeSweeperAuth;

    address internal composableCowMock = address(bytes20(bytes32("composableCowMock")));
    address internal vaultRelayerMock = address(bytes20(bytes32("vaultRelayerMock")));
    address internal feeRecipient;

    ICowSwapFeeBurner internal cowSwapFeeBurner;
    IProtocolFeeSweeper internal feeSweeper;

    function setUp() public override {
        BaseVaultTest.setUp();

        orderDeadline = block.timestamp + ORDER_LIFETIME;

        (feeRecipient, ) = makeAddrAndKey("feeRecipient");

        // Only fee sweeper can call `burn`, so for simplicity we just make the admin the fee sweeper for the purpose
        // of this test.
        cowSwapFeeBurner = new ERC4626CowSwapFeeBurner(
            IProtocolFeeSweeper(admin),
            IComposableCow(composableCowMock),
            vaultRelayerMock,
            APP_DATA_HASH,
            bob,
            VERSION
        );
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

        vm.prank(admin);
        waDAI.approve(address(cowSwapFeeBurner), TEST_BURN_AMOUNT);

        vm.expectRevert(
            abi.encodeWithSelector(
                ICowSwapFeeBurner.OrderHasUnexpectedStatus.selector,
                ICowSwapFeeBurner.OrderStatus.Active
            )
        );
        vm.prank(admin);
        cowSwapFeeBurner.burn(
            address(0),
            waDAI,
            TEST_BURN_AMOUNT,
            usdc,
            _encodeMinAmountsOut(MIN_TARGET_TOKEN_AMOUNT, 0),
            alice,
            orderDeadline
        );
    }

    function _testBurn() public {
        // Admin will call `burn` acting as the fee sweeper. The burner will pull tokens from them.
        vm.prank(admin);
        waDAI.approve(address(cowSwapFeeBurner), TEST_BURN_AMOUNT);

        uint256 cowSwapFeeBurnerWaDaiBalanceBefore = waDAI.balanceOf(address(cowSwapFeeBurner));
        uint256 cowSwapFeeBurnerDaiBalanceBefore = dai.balanceOf(address(cowSwapFeeBurner));
        uint256 callerWaDaiBalanceBefore = waDAI.balanceOf(address(admin));

        _mockComposableCowCreate(dai);

        uint256 assetsAmount = waDAI.previewRedeem(TEST_BURN_AMOUNT);
        require(assetsAmount != TEST_BURN_AMOUNT, "No point testing when rate is 1:1");

        vm.expectEmit();
        emit IProtocolFeeBurner.ProtocolFeeBurned(address(0), dai, assetsAmount, usdc, MIN_TARGET_TOKEN_AMOUNT, alice);

        vm.prank(admin);
        cowSwapFeeBurner.burn(
            address(0),
            waDAI,
            TEST_BURN_AMOUNT,
            usdc,
            _encodeMinAmountsOut(MIN_TARGET_TOKEN_AMOUNT, 0),
            alice,
            orderDeadline
        );

        assertEq(
            waDAI.balanceOf(admin),
            callerWaDaiBalanceBefore - TEST_BURN_AMOUNT,
            "caller should have sent the fee to the burner"
        );

        assertEq(
            waDAI.balanceOf(address(cowSwapFeeBurner)),
            cowSwapFeeBurnerWaDaiBalanceBefore,
            "cowSwapFeeBurner should have received _and redeemed_ the fee"
        );

        assertEq(
            dai.balanceOf(address(cowSwapFeeBurner)),
            cowSwapFeeBurnerDaiBalanceBefore + assetsAmount,
            "cowSwapFeeBurner should have received the fee"
        );

        assertEq(waDAI.allowance(admin, address(cowSwapFeeBurner)), 0, "Hanging allowance between caller and burner");

        assertEq(
            dai.allowance(address(cowSwapFeeBurner), vaultRelayerMock),
            assetsAmount,
            "vaultRelayer should have been approved to transfer the fee"
        );

        GPv2Order memory order = cowSwapFeeBurner.getOrder(dai);
        GPv2Order memory expectedOrder = GPv2Order({
            sellToken: IERC20(address(dai)),
            buyToken: IERC20(address(usdc)),
            receiver: alice,
            sellAmount: assetsAmount,
            buyAmount: MIN_TARGET_TOKEN_AMOUNT,
            validTo: uint32(orderDeadline),
            appData: APP_DATA_HASH,
            feeAmount: 0,
            kind: SELL_KIND,
            partiallyFillable: true,
            sellTokenBalance: TOKEN_BALANCE,
            buyTokenBalance: TOKEN_BALANCE
        });

        assertEq(keccak256(abi.encode(order)), keccak256(abi.encode(expectedOrder)), "Order has incorrect values");
        assertEq(
            uint256(cowSwapFeeBurner.getOrderStatus(dai)),
            uint256(ICowSwapFeeBurner.OrderStatus.Active),
            "Order status should be Active"
        );
    }

    /// @dev No order is created in this case; tokens are forwarded to the receiver directly.
    function testBurnFeeTokenIsTargetToken() public {
        // Admin will call `burn` acting as the fee sweeper. The burner will pull tokens from them.
        vm.prank(admin);
        waDAI.approve(address(cowSwapFeeBurner), TEST_BURN_AMOUNT);

        uint256 cowSwapFeeBurnerWaDaiBalanceBefore = waDAI.balanceOf(address(cowSwapFeeBurner));
        uint256 cowSwapFeeBurnerDaiBalanceBefore = dai.balanceOf(address(cowSwapFeeBurner));
        uint256 callerWaDaiBalanceBefore = waDAI.balanceOf(address(admin));
        uint256 receiverDaiBalanceBefore = dai.balanceOf(alice);

        uint256 assetsAmount = waDAI.previewRedeem(TEST_BURN_AMOUNT);
        require(assetsAmount != TEST_BURN_AMOUNT, "No point testing when rate is 1:1");

        // Target token is now DAI, which is waDAI.asset().
        // Deadline doesn't matter in this case, as settlement is instant.
        vm.prank(admin);
        cowSwapFeeBurner.burn(
            address(0),
            waDAI,
            TEST_BURN_AMOUNT,
            dai,
            _encodeMinAmountsOut(assetsAmount, 0),
            alice,
            0
        );

        assertEq(
            waDAI.balanceOf(admin),
            callerWaDaiBalanceBefore - TEST_BURN_AMOUNT,
            "caller should have sent the fee to the burner"
        );

        assertEq(
            waDAI.balanceOf(address(cowSwapFeeBurner)),
            cowSwapFeeBurnerWaDaiBalanceBefore,
            "cowSwapFeeBurner should have received _and redeemed_ the fee"
        );

        assertEq(
            dai.balanceOf(address(cowSwapFeeBurner)),
            cowSwapFeeBurnerDaiBalanceBefore,
            "cowSwapFeeBurner should have received _and forwarded_ the asset"
        );

        assertEq(waDAI.allowance(admin, address(cowSwapFeeBurner)), 0, "Hanging allowance between caller and burner");

        assertEq(
            dai.balanceOf(alice),
            receiverDaiBalanceBefore + assetsAmount,
            "Receiver should have gotten the redeemed assets directly"
        );

        vm.expectRevert(abi.encodeWithSelector(ICowConditionalOrder.OrderNotValid.selector, "Order does not exist"));
        cowSwapFeeBurner.getOrder(dai);
    }

    function testBurnFeeTokenIsTargetTokenBelowMin() public {
        // Admin will call `burn` acting as the fee sweeper. The burner will pull tokens from them.
        vm.prank(admin);
        waDAI.approve(address(cowSwapFeeBurner), TEST_BURN_AMOUNT);

        uint256 assetsAmount = waDAI.previewRedeem(TEST_BURN_AMOUNT);
        require(assetsAmount != TEST_BURN_AMOUNT, "No point testing when rate is 1:1");

        vm.expectRevert(
            abi.encodeWithSelector(IProtocolFeeBurner.AmountOutBelowMin.selector, dai, assetsAmount, assetsAmount + 1)
        );
        // Target token is now DAI, which is waDAI.asset().
        vm.prank(admin);
        cowSwapFeeBurner.burn(
            address(0),
            waDAI,
            TEST_BURN_AMOUNT,
            dai,
            _encodeMinAmountsOut(assetsAmount + 1, 0),
            alice,
            orderDeadline
        );
    }

    function testBurnFeeTokenIfUnwrappedTokenBelowMin() public {
        // Admin will call `burn` acting as the fee sweeper. The burner will pull tokens from them.
        vm.prank(admin);
        waDAI.approve(address(cowSwapFeeBurner), TEST_BURN_AMOUNT);

        uint256 assetsAmount = waDAI.previewRedeem(TEST_BURN_AMOUNT);
        require(assetsAmount != TEST_BURN_AMOUNT, "No point testing when rate is 1:1");

        vm.expectRevert(
            abi.encodeWithSelector(IProtocolFeeBurner.AmountOutBelowMin.selector, dai, assetsAmount, type(uint128).max)
        );
        // Target token is now DAI, which is waDAI.asset().
        vm.prank(admin);
        cowSwapFeeBurner.burn(
            address(0),
            waDAI,
            TEST_BURN_AMOUNT,
            dai,
            _encodeMinAmountsOut(MIN_TARGET_TOKEN_AMOUNT, type(uint128).max),
            alice,
            orderDeadline
        );
    }

    function testBurnFeeTokenIfUnwrappedTokenIsZero() public {
        // Admin will call `burn` acting as the fee sweeper. The burner will pull tokens from them.
        vm.prank(admin);
        waDAI.approve(address(cowSwapFeeBurner), TEST_BURN_AMOUNT);

        uint256 assetsAmount = waDAI.previewRedeem(TEST_BURN_AMOUNT);
        require(assetsAmount != TEST_BURN_AMOUNT, "No point testing when rate is 1:1");

        vm.mockCall(
            address(waDAI),
            abi.encodeWithSelector(
                IERC4626.redeem.selector,
                TEST_BURN_AMOUNT,
                address(cowSwapFeeBurner),
                address(cowSwapFeeBurner)
            ),
            abi.encode(0)
        );

        vm.expectRevert(abi.encodeWithSelector(ERC4626CowSwapFeeBurner.AmountOutIsZero.selector, dai));
        // Target token is now DAI, which is waDAI.asset().
        vm.prank(admin);
        cowSwapFeeBurner.burn(
            address(0),
            waDAI,
            TEST_BURN_AMOUNT,
            dai,
            _encodeMinAmountsOut(MIN_TARGET_TOKEN_AMOUNT, 0),
            alice,
            orderDeadline
        );
    }

    function _encodeMinAmountsOut(
        uint256 minTargetTokenAmountOut,
        uint256 minERC4626AmountOut
    ) internal pure returns (uint256) {
        return uint256(PackedTokenBalance.toPackedBalance(minTargetTokenAmountOut, minERC4626AmountOut));
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
}
