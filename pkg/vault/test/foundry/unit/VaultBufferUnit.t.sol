// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { ERC4626TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC4626TestToken.sol";

import { IBatchRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IBatchRouter.sol";

import { BaseVaultTest } from "../utils/BaseVaultTest.sol";

contract VaultBufferUnitTest is BaseVaultTest {
    ERC4626TestToken internal wDaiInitialized;
    ERC4626TestToken internal wUSDCNotInitialized;

    uint256 private constant _userAmount = 10e6 * 1e18;
    uint256 private constant _wrapAmount = _userAmount / 100;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        _createWrappedToken();
        _mintTokensToLpAndYBProtocol();
        _initializeBuffer();
    }

    function testUnderlyingSurplusBalanceZero() public view {
        uint256 surplus = vault.internalGetBufferUnderlyingSurplus(IERC4626(address(wUSDCNotInitialized)));
        assertEq(surplus, 0, "Wrong underlying surplus");
    }

    function testUnderlyingSurplusWrongBalance() public {
        // Unbalances buffer so that buffer has less underlying than wrapped.
        IBatchRouter.SwapPathExactAmountIn[] memory paths = _exactInWrapUnwrapPath(
            _wrapAmount / 2,
            0,
            IERC20(address(wDaiInitialized)),
            dai,
            IERC20(address(wDaiInitialized))
        );

        vm.prank(lp);
        batchRouter.swapExactIn(paths, MAX_UINT256, false, bytes(""));

        uint256 surplus = vault.internalGetBufferUnderlyingSurplus(IERC4626(address(wDaiInitialized)));
        assertEq(surplus, 0, "Wrong underlying surplus");
    }

    function testUnderlyingSurplusCorrectBalance() public {
        // Unbalances buffer so that buffer has more underlying than wrapped (so it has a surplus of underlying).
        IBatchRouter.SwapPathExactAmountIn[] memory paths = _exactInWrapUnwrapPath(
            _wrapAmount / 2,
            0,
            dai,
            IERC20(address(wDaiInitialized)),
            IERC20(address(wDaiInitialized))
        );

        vm.startPrank(lp);
        batchRouter.swapExactIn(paths, MAX_UINT256, false, bytes(""));

        // rate = assets / supply. If we double the assets, we double the rate.
        // Donate to wrapped token to inflate rate to 2
        dai.transfer(address(wDaiInitialized), wDaiInitialized.totalAssets());
        vm.stopPrank();

        assertApproxEqAbs(wDaiInitialized.getRate(), 2e18, 1, "Wrong wDAI rate");

        uint256 surplus = vault.internalGetBufferUnderlyingSurplus(IERC4626(address(wDaiInitialized)));
        // Before swap, buffer had _wrapAmount of underlying and wrapped.
        // After swap, buffer has 3/2 _wrapAmount of underlying and 1/2 _wrapAmount of wrapped
        // surplus = (3/2 _wrapAmount - (1/2 _wrapAmount * rate)) / 2 = 1/4 _wrapAmount.
        assertApproxEqAbs(surplus, _wrapAmount / 4, 1, "Wrong underlying surplus");
    }

    function testWrappedSurplusBalanceZero() public view {
        uint256 surplus = vault.internalGetBufferWrappedSurplus(IERC4626(address(wUSDCNotInitialized)));
        assertEq(surplus, 0, "Wrong wrapped surplus");
    }

    function testWrappedSurplusWrongBalance() public {
        // Unbalances buffer so that buffer has more underlying than wrapped.
        IBatchRouter.SwapPathExactAmountIn[] memory paths = _exactInWrapUnwrapPath(
            _wrapAmount / 2,
            0,
            dai,
            IERC20(address(wDaiInitialized)),
            IERC20(address(wDaiInitialized))
        );

        vm.prank(lp);
        batchRouter.swapExactIn(paths, MAX_UINT256, false, bytes(""));

        uint256 surplus = vault.internalGetBufferWrappedSurplus(IERC4626(address(wDaiInitialized)));
        assertEq(surplus, 0, "Wrong wrapped surplus");
    }

    function testWrappedSurplusCorrectBalance() public {
        // Unbalances buffer so that buffer has less underlying than wrapped (so it has a surplus of wrapped).
        IBatchRouter.SwapPathExactAmountIn[] memory paths = _exactInWrapUnwrapPath(
            _wrapAmount / 2,
            0,
            IERC20(address(wDaiInitialized)),
            dai,
            IERC20(address(wDaiInitialized))
        );

        vm.startPrank(lp);
        batchRouter.swapExactIn(paths, MAX_UINT256, false, bytes(""));

        // rate = assets / supply. If we double the assets, we double the rate.
        // Donate to wrapped token to inflate rate to 2.
        dai.transfer(address(wDaiInitialized), wDaiInitialized.totalAssets());
        vm.stopPrank();

        assertApproxEqAbs(wDaiInitialized.getRate(), 2e18, 1, "Wrong wDAI rate");

        uint256 surplus = vault.internalGetBufferWrappedSurplus(IERC4626(address(wDaiInitialized)));
        // Before swap, buffer had _wrapAmount of underlying and wrapped.
        // After swap, buffer has 1/2 _wrapAmount of underlying and 3/2 _wrapAmount of wrapped
        // surplus = (3/2 _wrapAmount - (1/2 _wrapAmount / rate)) / 2 = 5/8 _wrapAmount.
        assertApproxEqAbs(surplus, (5 * _wrapAmount) / 8, 1, "Wrong wrapped surplus");
    }

    function testReservesAfterWrappingWithVaultBalances() public {
        uint256 underlyingDeposited = 4e6;
        uint256 wrappedMinted = 2e5;

        // Simulate a wrapping operation.

        // 1) Vault deposits underlying tokens into yield bearing protocol (a.k.a. Bob).
        vault.manualTransfer(dai, bob, underlyingDeposited);

        vm.prank(bob);
        // 2) Yield bearing protocol transfers wrapped tokens to vault (simulating a yield-bearing protocol).
        IERC20(address(wDaiInitialized)).transfer(address(vault), wrappedMinted);

        // Measure reserves.
        uint256 wrappedReservesBefore = vault.getReservesOf(IERC20(address(wDaiInitialized)));
        uint256 underlyingReservesBefore = vault.getReservesOf(dai);

        // Call _updateReservesAfterWrapping.
        (uint256 actualUnderlying, uint256 actualWrapped) = vault.manualUpdateReservesAfterWrapping(
            dai,
            IERC20(address(wDaiInitialized))
        );

        // Measure output of _updateReservesAfterWrapping.
        assertEq(actualUnderlying, underlyingDeposited, "Wrong underlying deposited");
        assertEq(actualWrapped, wrappedMinted, "Wrong wrapped minted");

        // Measure reserves
        uint256 wrappedReservesAfter = vault.getReservesOf(IERC20(address(wDaiInitialized)));
        uint256 underlyingReservesAfter = vault.getReservesOf(dai);

        assertEq(
            underlyingReservesBefore - underlyingReservesAfter,
            underlyingDeposited,
            "Wrong reserves of underlying"
        );
        assertEq(wrappedReservesAfter - wrappedReservesBefore, wrappedMinted, "Wrong reserves of wrapped");
    }

    function testReservesAfterUnwrapping() public {
        uint256 underlyingWithdrawn = 4e6;
        uint256 wrappedBurned = 2e5;

        // Simulate a wrapping operation.

        // 1) Vault burns wrapped tokens (simulated by depositing to Bob, the YB Protocol).
        vault.manualTransfer(IERC20(address(wDaiInitialized)), bob, wrappedBurned);

        vm.prank(bob);
        // 2) Yield bearing protocol transfers underlying tokens to vault (simulating a yield-bearing protocol).
        dai.transfer(address(vault), underlyingWithdrawn);

        // Measure reserves
        uint256 wrappedReservesBefore = vault.getReservesOf(IERC20(address(wDaiInitialized)));
        uint256 underlyingReservesBefore = vault.getReservesOf(dai);

        // Call _updateReservesAfterWrapping
        (uint256 actualUnderlying, uint256 actualWrapped) = vault.manualUpdateReservesAfterWrapping(
            dai,
            IERC20(address(wDaiInitialized))
        );

        // Measure output of _updateReservesAfterWrapping
        assertEq(actualUnderlying, underlyingWithdrawn, "Wrong underlying deposited");
        assertEq(actualWrapped, wrappedBurned, "Wrong wrapped minted");

        // Measure reserves
        uint256 wrappedReservesAfter = vault.getReservesOf(IERC20(address(wDaiInitialized)));
        uint256 underlyingReservesAfter = vault.getReservesOf(dai);

        assertEq(
            underlyingReservesAfter - underlyingReservesBefore,
            underlyingWithdrawn,
            "Wrong reserves of underlying"
        );
        assertEq(wrappedReservesBefore - wrappedReservesAfter, wrappedBurned, "Wrong reserves of wrapped");
    }

    function _createWrappedToken() private {
        wDaiInitialized = new ERC4626TestToken(dai, "Wrapped DAI", "wDAI", 18);
        vm.label(address(wDaiInitialized), "wToken");

        // "USDC" is deliberately 18 decimals to test one thing at a time.
        wUSDCNotInitialized = new ERC4626TestToken(usdc, "Wrapped USDC", "wUSDC", 18);
        vm.label(address(wUSDCNotInitialized), "wUSDC");
    }

    function _mintTokensToLpAndYBProtocol() private {
        // Fund LP
        vm.startPrank(lp);

        dai.mint(lp, 3 * _userAmount);
        dai.approve(address(wDaiInitialized), _userAmount);
        wDaiInitialized.deposit(_userAmount, lp);

        usdc.mint(lp, 3 * _userAmount);
        usdc.approve(address(wUSDCNotInitialized), _userAmount);
        wUSDCNotInitialized.deposit(_userAmount, lp);

        wDaiInitialized.approve(address(permit2), MAX_UINT256);
        permit2.approve(address(wDaiInitialized), address(router), type(uint160).max, type(uint48).max);
        permit2.approve(address(wDaiInitialized), address(batchRouter), type(uint160).max, type(uint48).max);
        wUSDCNotInitialized.approve(address(permit2), MAX_UINT256);
        permit2.approve(address(wUSDCNotInitialized), address(router), type(uint160).max, type(uint48).max);
        permit2.approve(address(wUSDCNotInitialized), address(batchRouter), type(uint160).max, type(uint48).max);
        vm.stopPrank();

        // Fund a yield-bearing protocol, in this case represented by Bob.
        vm.startPrank(bob);

        dai.mint(bob, 3 * _userAmount);
        dai.approve(address(wDaiInitialized), _userAmount);
        wDaiInitialized.deposit(_userAmount, bob);

        usdc.mint(bob, 3 * _userAmount);
        usdc.approve(address(wUSDCNotInitialized), _userAmount);
        wUSDCNotInitialized.deposit(_userAmount, bob);

        wDaiInitialized.approve(address(permit2), MAX_UINT256);
        permit2.approve(address(wDaiInitialized), address(router), type(uint160).max, type(uint48).max);
        permit2.approve(address(wDaiInitialized), address(batchRouter), type(uint160).max, type(uint48).max);
        wUSDCNotInitialized.approve(address(permit2), MAX_UINT256);
        permit2.approve(address(wUSDCNotInitialized), address(router), type(uint160).max, type(uint48).max);
        permit2.approve(address(wUSDCNotInitialized), address(batchRouter), type(uint160).max, type(uint48).max);
        vm.stopPrank();
    }

    function _initializeBuffer() private {
        vm.prank(lp);
        router.addLiquidityToBuffer(IERC4626(address(wDaiInitialized)), _wrapAmount, _wrapAmount, lp);
    }

    function _exactInWrapUnwrapPath(
        uint256 exactAmountIn,
        uint256 minAmountOut,
        IERC20 tokenFrom,
        IERC20 tokenTo,
        IERC20 wrappedToken
    ) private pure returns (IBatchRouter.SwapPathExactAmountIn[] memory paths) {
        IBatchRouter.SwapPathStep[] memory steps = new IBatchRouter.SwapPathStep[](1);
        paths = new IBatchRouter.SwapPathExactAmountIn[](1);

        steps[0] = IBatchRouter.SwapPathStep({ pool: address(wrappedToken), tokenOut: tokenTo, isBuffer: true });

        paths[0] = IBatchRouter.SwapPathExactAmountIn({
            tokenIn: tokenFrom,
            steps: steps,
            exactAmountIn: exactAmountIn,
            minAmountOut: minAmountOut
        });
    }
}
