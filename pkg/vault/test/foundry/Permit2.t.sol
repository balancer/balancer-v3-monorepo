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

    PoolMock internal wethPool;
    PoolMock internal wethPoolNoInit;

    // Track the indices for the local dai/weth pool.
    uint256 internal daiIdxWethPool;
    uint256 internal wethIdx;

    // Track the indices for the standard dai/usdc pool.
    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    uint256[] internal wethDaiAmountsIn;
    IERC20[] internal wethDaiTokens;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        approveForPool(IERC20(wethPool));
    }

    function createPool() internal override returns (address) {
        PoolMock newPool = new PoolMock(
            IVault(address(vault)),
            "ERC20 Pool",
            "ERC20POOL",
            vault.buildTokenConfig([address(dai), address(usdc)].toMemoryArray().asIERC20()),
            true,
            365 days,
            address(0)
        );
        vm.label(address(newPool), "pool");

        wethPool = new PoolMock(
            IVault(address(vault)),
            "ERC20 weth Pool",
            "ERC20POOL",
            vault.buildTokenConfig([address(weth), address(dai)].toMemoryArray().asIERC20()),
            true,
            365 days,
            address(0)
        );
        vm.label(address(wethPool), "wethPool");

        (daiIdxWethPool, wethIdx) = getSortedIndexes(address(dai), address(weth));
        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));

        wethDaiTokens = InputHelpers.sortTokens([address(weth), address(dai)].toMemoryArray().asIERC20());

        wethDaiAmountsIn = new uint256[](2);
        wethDaiAmountsIn[wethIdx] = ethAmountIn;
        wethDaiAmountsIn[daiIdxWethPool] = daiAmountIn;

        wethPoolNoInit = new PoolMock(
            IVault(address(vault)),
            "ERC20 weth Pool",
            "ERC20POOL",
            vault.buildTokenConfig([address(weth), address(dai)].toMemoryArray().asIERC20()),
            true,
            365 days,
            address(0)
        );
        vm.label(address(wethPoolNoInit), "wethPoolNoInit");

        return address(newPool);
    }

    function initPool() internal override {
        (IERC20[] memory tokens, , , , ) = vault.getPoolTokenInfo(address(pool));
        vm.prank(lp);
        router.initialize(address(pool), tokens, [poolInitAmount, poolInitAmount].toMemoryArray(), 0, false, "");

        vm.prank(lp);
        bool wethIsEth = true;
        router.initialize{ value: ethAmountIn }(
            address(wethPool),
            wethDaiTokens,
            wethDaiAmountsIn,
            initBpt,
            wethIsEth,
            bytes("")
        );
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

    function testPermitAndCall() public {
        // Revoke allowance
        vm.prank(alice);
        permit2.approve(address(usdc), address(router), 0, 0);

        (uint160 amount, , ) = permit2.allowance(alice, address(usdc), address(router));
        assertEq(amount, 0);

        bytes[] memory data = new bytes[](1);
        bytes memory sig = getPermit2Signature(
            address(router),
            address(usdc),
            uint160(defaultAmount),
            type(uint48).max,
            0,
            aliceKey
        );

        IAllowanceTransfer.PermitSingle memory permit = getSinglePermit2(
            address(router),
            address(usdc),
            uint160(defaultAmount),
            type(uint48).max,
            0
        );

        data[0] = abi.encodeWithSelector(
            IRouter.swapSingleTokenExactIn.selector,
            address(pool),
            usdc,
            dai,
            defaultAmount,
            defaultAmount,
            type(uint256).max,
            false,
            bytes("")
        );

        vm.prank(alice);
        router.permitAndCall(permit, sig, data);

        (amount, , ) = permit2.allowance(alice, address(usdc), address(router));
        // Allowance is spent
        assertEq(amount, 0);
    }

    function testPermitBatchAndCall() public {
        // Revoke allowance
        vm.prank(alice);
        permit2.approve(address(usdc), address(router), 0, 0);
        vm.prank(alice);
        permit2.approve(address(dai), address(router), 0, 0);

        (uint160 amount, , ) = permit2.allowance(alice, address(usdc), address(router));
        assertEq(amount, 0);
        (amount, , ) = permit2.allowance(alice, address(dai), address(router));
        assertEq(amount, 0);

        bptAmountOut = defaultAmount * 2;
        uint256[] memory amountsIn = [uint256(defaultAmount), uint256(defaultAmount)].toMemoryArray();

        bytes[] memory data = new bytes[](1);
        bytes memory sig = getPermit2BatchSignature(
            address(router),
            [address(usdc), address(dai)].toMemoryArray(),
            uint160(defaultAmount),
            type(uint48).max,
            0,
            aliceKey
        );

        IAllowanceTransfer.PermitBatch memory permit = getPermit2Batch(
            address(router),
            [address(usdc), address(dai)].toMemoryArray(),
            uint160(defaultAmount),
            type(uint48).max,
            0
        );

        data[0] = abi.encodeWithSelector(
            IRouter.addLiquidityUnbalanced.selector,
            address(pool),
            amountsIn,
            bptAmountOut,
            false,
            bytes("")
        );

        vm.prank(alice);
        router.permitBatchAndCall(permit, sig, data);

        // Alice has BPT
        assertEq(bptAmountOut, IERC20(pool).balanceOf(alice), "Alice has wrong about of pool tokens");

        (amount, , ) = permit2.allowance(alice, address(dai), address(router));
        // Allowance is spent
        assertEq(amount, 0, "DAI allowance is not spent");

        (amount, , ) = permit2.allowance(alice, address(usdc), address(router));
        // Allowance is spent
        assertEq(amount, 0, "USDC allowance is not spent");
    }
}
