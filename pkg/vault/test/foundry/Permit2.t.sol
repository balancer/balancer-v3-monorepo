// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import { GasSnapshot } from "forge-gas-snapshot/GasSnapshot.sol";
import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";
import { IAllowanceTransfer } from "permit2/src/interfaces/IAllowanceTransfer.sol";

import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IRouter.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IERC20MultiToken } from "@balancer-labs/v3-interfaces/contracts/vault/IERC20MultiToken.sol";
import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { EVMCallModeHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/EVMCallModeHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";

import { BalancerPoolToken } from "vault/contracts/BalancerPoolToken.sol";
import { PoolMock } from "../../contracts/test/PoolMock.sol";
import { Router } from "../../contracts/Router.sol";
import { RouterCommon } from "../../contracts/RouterCommon.sol";
import { VaultMock } from "../../contracts/test/VaultMock.sol";
import { VaultExtensionMock } from "../../contracts/test/VaultExtensionMock.sol";

import { VaultMockDeployer } from "./utils/VaultMockDeployer.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract Permit2Test is BaseVaultTest {
    using ArrayHelpers for *;

    uint256 internal usdcAmountIn = 1e3 * 1e6;
    uint256 internal daiAmountIn = 1e3 * 1e18;
    uint256 internal daiAmountOut = 1e2 * 1e18;
    uint256 internal ethAmountIn = 1e3 ether;
    uint256 internal initBpt = 10e18;
    uint256 internal bptAmountOut = 1e18;

    function setUp() public virtual override {
        BaseVaultTest.setUp();
    }

    function testNoPermitCall() public {
        // Revoke allowance
        vm.prank(alice);
        permit2.approve(address(usdc), address(router), 0, 0);

        (uint160 amount, , ) = permit2.allowance(alice, address(usdc), address(router));
        assertEq(amount, 0);

        vm.expectRevert(abi.encodeWithSelector(IAllowanceTransfer.AllowanceExpired.selector, 0));
        router.swapSingleTokenExactIn(
            address(pool),
            usdc,
            dai,
            defaultAmount,
            defaultAmount,
            MAX_UINT256,
            false,
            bytes("")
        );
    }

    function testPermitBatchAndCall() public {
        // Revoke allowance
        vm.prank(alice);
        permit2.approve(address(usdc), address(router), 0, 0);
        vm.prank(alice);
        permit2.approve(address(dai), address(router), 0, 0);
        vm.prank(alice);
        IERC20(pool).approve(address(router), 0);

        (uint160 amount, , ) = permit2.allowance(alice, address(usdc), address(router));
        assertEq(amount, 0);
        (amount, , ) = permit2.allowance(alice, address(dai), address(router));
        assertEq(amount, 0);
        assertEq(IERC20(pool).allowance(alice, address(router)), 0, "Router allowance is not zero");

        bptAmountOut = defaultAmount * 2;
        uint256[] memory amountsIn = [uint256(defaultAmount), uint256(defaultAmount)].toMemoryArray();

        IRouter.PermitApproval[] memory permitBatch = new IRouter.PermitApproval[](1);
        permitBatch[0] = IRouter.PermitApproval(pool, alice, address(router), bptAmountOut, 0, block.timestamp);

        bytes[] memory permitSignatures = new bytes[](1);
        (uint8 v, bytes32 r, bytes32 s) = getPermitSignature(
            BalancerPoolToken(address(pool)),
            alice,
            address(router),
            bptAmountOut,
            0,
            block.timestamp,
            aliceKey
        );
        permitSignatures[0] = abi.encodePacked(r, s, v);

        IAllowanceTransfer.PermitBatch memory permit2Batch = getPermit2Batch(
            address(router),
            [address(usdc), address(dai)].toMemoryArray(),
            uint160(defaultAmount),
            type(uint48).max,
            0
        );

        bytes memory permit2Signature = getPermit2BatchSignature(
            address(router),
            [address(usdc), address(dai)].toMemoryArray(),
            uint160(defaultAmount),
            type(uint48).max,
            0,
            aliceKey
        );

        bytes[] memory multicallData = new bytes[](2);
        multicallData[0] = abi.encodeWithSelector(
            IRouter.addLiquidityUnbalanced.selector,
            address(pool),
            amountsIn,
            bptAmountOut,
            false,
            bytes("")
        );

        uint256[] memory minAmountsOut = [uint256(defaultAmount), uint256(defaultAmount)].toMemoryArray();
        multicallData[1] = abi.encodeWithSelector(
            IRouter.removeLiquidityProportional.selector,
            address(pool),
            bptAmountOut,
            minAmountsOut,
            false,
            bytes("")
        );

        vm.prank(alice);
        router.permitBatchAndCall(permitBatch, permitSignatures, permit2Batch, permit2Signature, multicallData);

        // Alice has no BPT
        assertEq(IERC20(pool).balanceOf(alice), 0, "Alice has pool tokens");

        (amount, , ) = permit2.allowance(alice, address(dai), address(router));
        // Allowance is spent
        assertEq(amount, 0, "DAI allowance is not spent");

        (amount, , ) = permit2.allowance(alice, address(usdc), address(router));
        // Allowance is spent
        assertEq(amount, 0, "USDC allowance is not spent");
    }
}
