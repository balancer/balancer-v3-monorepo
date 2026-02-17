// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { ISenderGuard } from "@balancer-labs/v3-interfaces/contracts/vault/ISenderGuard.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";

import { LBPKYCHook } from "../../contracts/LBPKYCHook.sol";

contract LBPKYCHookTest is BaseVaultTest {
    uint256 internal constant MAX_CAP_RAW = 1000e18;

    LBPKYCHook internal hook;
    LBPKYCHook internal hookNoCap;

    uint256 internal signerPk;
    address internal signerAddr;
    address internal lbpPool;

    // `dai` is used as the capped (project) token; `usdc` as the reserve token.

    function setUp() public override {
        super.setUp();

        signerPk = 0xdeadbeef;
        signerAddr = vm.addr(signerPk);
        lbpPool = makeAddr("lbpPool");

        // Hook with cap enabled.
        hook = new LBPKYCHook(IVault(address(vault)), address(router), dai, MAX_CAP_RAW, signerAddr);

        // Hook with cap disabled (KYC-only mode).
        hookNoCap = new LBPKYCHook(IVault(address(vault)), address(router), dai, MAX_UINT256, signerAddr);

        // Register both hooks so `onlyAuthorizedCaller` passes.
        _registerHook(hook);
        _registerHook(hookNoCap);
    }

    function _registerHook(LBPKYCHook hookToRegister) internal {
        vm.prank(address(vault));
        hookToRegister.onRegister(
            address(this),
            lbpPool,
            new TokenConfig[](2),
            LiquidityManagement(false, false, false, false)
        );
    }

    function testConstructorSetsImmutables() public view {
        assertEq(
            hook.KYC_AUTHORIZATION_TYPEHASH(),
            keccak256("KYCAuthorization(address user,address pool,uint256 deadline)")
        );
        assertNotEq(hook.domainSeparator(), bytes32(0));
    }

    /***************************************************************************
                                  getHookFlags
    ***************************************************************************/

    function testHookFlagsWithCap() public view {
        HookFlags memory flags = hook.getHookFlags();

        assertTrue(flags.shouldCallBeforeSwap, "shouldCallBeforeSwap should be true");
        assertTrue(flags.shouldCallAfterSwap, "shouldCallAfterSwap should be true");
        assertFalse(flags.shouldCallBeforeInitialize, "shouldCallBeforeInitialize should be false");
        assertFalse(flags.shouldCallAfterInitialize, "shouldCallAfterInitialize should be false");
        assertFalse(flags.shouldCallBeforeAddLiquidity, "shouldCallBeforeAddLiquidity should be false");
        assertFalse(flags.shouldCallAfterAddLiquidity, "shouldCallAfterAddLiquidity should be false");
        assertFalse(flags.shouldCallBeforeRemoveLiquidity, "shouldCallBeforeRemoveLiquidity should be false");
        assertFalse(flags.shouldCallAfterRemoveLiquidity, "shouldCallAfterRemoveLiquidity should be false");
        assertFalse(flags.shouldCallComputeDynamicSwapFee, "shouldCallComputeDynamicSwapFee should be false");
    }

    function testHookFlagsWithoutCap() public view {
        HookFlags memory flags = hookNoCap.getHookFlags();

        assertTrue(flags.shouldCallBeforeSwap, "shouldCallBeforeSwap should be true");
        assertFalse(flags.shouldCallAfterSwap, "shouldCallAfterSwap should be false");
    }

    /***************************************************************************
                          onBeforeSwap — KYC Enforcement
    ***************************************************************************/

    function testOnBeforeSwapValidSignature() public {
        uint256 deadline = block.timestamp + 1 hours;
        _mockGetSender(alice);

        bytes memory sig = _signKYC(signerPk, hook, alice, lbpPool, deadline);
        bytes memory userData = _encodeUserData(deadline, sig);
        PoolSwapParams memory params = _buildSwapParams(address(router), userData);

        vm.prank(address(vault));
        assertTrue(hook.onBeforeSwap(params, lbpPool));
    }

    function testOnBeforeSwapRouterNotTrusted() public {
        address untrustedRouter = makeAddr("untrustedRouter");
        uint256 deadline = block.timestamp + 1 hours;

        bytes memory sig = _signKYC(signerPk, hook, alice, lbpPool, deadline);
        bytes memory userData = _encodeUserData(deadline, sig);
        PoolSwapParams memory params = _buildSwapParams(untrustedRouter, userData);

        vm.expectRevert(abi.encodeWithSelector(LBPKYCHook.RouterNotTrusted.selector, untrustedRouter));

        vm.prank(address(vault));
        hook.onBeforeSwap(params, lbpPool);
    }

    function testOnBeforeSwapExpired() public {
        uint256 deadline = block.timestamp - 1;
        _mockGetSender(alice);

        bytes memory sig = _signKYC(signerPk, hook, alice, lbpPool, deadline);
        bytes memory userData = _encodeUserData(deadline, sig);
        PoolSwapParams memory params = _buildSwapParams(address(router), userData);

        vm.expectRevert(LBPKYCHook.KYCExpired.selector);

        vm.prank(address(vault));
        hook.onBeforeSwap(params, lbpPool);
    }

    function testOnBeforeSwapUnauthorizedSigner() public {
        uint256 bogusPk = 0xDEAD;
        address bogusAddr = vm.addr(bogusPk);
        uint256 deadline = block.timestamp + 1 hours;
        _mockGetSender(alice);

        bytes memory sig = _signKYC(bogusPk, hook, alice, lbpPool, deadline);
        bytes memory userData = _encodeUserData(deadline, sig);
        PoolSwapParams memory params = _buildSwapParams(address(router), userData);

        vm.expectRevert(abi.encodeWithSelector(LBPKYCHook.UnauthorizedSigner.selector, bogusAddr));

        vm.prank(address(vault));
        hook.onBeforeSwap(params, lbpPool);
    }

    function testOnBeforeSwapSignedForDifferentUser() public {
        uint256 deadline = block.timestamp + 1 hours;

        // Signature is for alice, but the sender is bob.
        bytes memory sig = _signKYC(signerPk, hook, alice, lbpPool, deadline);
        bytes memory userData = _encodeUserData(deadline, sig);
        PoolSwapParams memory params = _buildSwapParams(address(router), userData);

        _mockGetSender(bob);

        // The recovered signer won't match because the struct hash includes the wrong user.
        vm.expectRevert();

        vm.prank(address(vault));
        hook.onBeforeSwap(params, lbpPool);
    }

    function testOnBeforeSwapSignedForDifferentPool() public {
        address otherPool = makeAddr("otherPool");
        uint256 deadline = block.timestamp + 1 hours;
        _mockGetSender(alice);

        // Signed for otherPool, but calling with lbpPool.
        bytes memory sig = _signKYC(signerPk, hook, alice, otherPool, deadline);
        bytes memory userData = _encodeUserData(deadline, sig);
        PoolSwapParams memory params = _buildSwapParams(address(router), userData);

        vm.expectRevert();

        vm.prank(address(vault));
        hook.onBeforeSwap(params, lbpPool);
    }

    function testOnBeforeSwapSignedForDifferentHook() public {
        uint256 deadline = block.timestamp + 1 hours;
        _mockGetSender(alice);

        // Signed against hookNoCap's domain, but called on hook.
        bytes memory sig = _signKYC(signerPk, hookNoCap, alice, lbpPool, deadline);
        bytes memory userData = _encodeUserData(deadline, sig);
        PoolSwapParams memory params = _buildSwapParams(address(router), userData);

        vm.expectRevert();

        vm.prank(address(vault));
        hook.onBeforeSwap(params, lbpPool);
    }

    function testOnBeforeSwapAcceptsExactDeadline() public {
        uint256 deadline = block.timestamp; // exactly now — should pass (<=)
        _mockGetSender(alice);

        bytes memory sig = _signKYC(signerPk, hook, alice, lbpPool, deadline);
        bytes memory userData = _encodeUserData(deadline, sig);
        PoolSwapParams memory params = _buildSwapParams(address(router), userData);

        vm.prank(address(vault));
        assertTrue(hook.onBeforeSwap(params, lbpPool));
    }

    function testOnBeforeSwapSignatureReusable() public {
        uint256 deadline = block.timestamp + 1 hours;
        _mockGetSender(alice);

        bytes memory sig = _signKYC(signerPk, hook, alice, lbpPool, deadline);
        bytes memory userData = _encodeUserData(deadline, sig);
        PoolSwapParams memory params = _buildSwapParams(address(router), userData);

        // Same signature works on consecutive calls.
        vm.startPrank(address(vault));
        assertTrue(hook.onBeforeSwap(params, lbpPool));
        assertTrue(hook.onBeforeSwap(params, lbpPool));
        vm.stopPrank();
    }

    /***************************************************************************
                          onAfterSwap — Cap Enforcement
    ***************************************************************************/

    function testOnAfterSwapTracksAllocation() public {
        uint256 buyAmount = 200e18;
        _mockGetSender(alice);

        AfterSwapParams memory params = _buildAfterSwapParams(usdc, dai, buyAmount, address(router), lbpPool);

        vm.prank(address(vault));
        (bool success, ) = hook.onAfterSwap(params);

        assertTrue(success);
        assertEq(hook.remainingAllocation(alice), MAX_CAP_RAW - buyAmount);
    }

    function testOnAfterSwapAllowsMultiplePurchasesUpToCap() public {
        _mockGetSender(alice);

        // First purchase: 600.
        AfterSwapParams memory params1 = _buildAfterSwapParams(usdc, dai, 600e18, address(router), lbpPool);
        vm.prank(address(vault));
        hook.onAfterSwap(params1);

        // Second purchase: 400 (total = 1000 = cap).
        AfterSwapParams memory params2 = _buildAfterSwapParams(usdc, dai, 400e18, address(router), lbpPool);
        vm.prank(address(vault));
        (bool success, ) = hook.onAfterSwap(params2);

        assertTrue(success);
        assertEq(hook.remainingAllocation(alice), 0);
    }

    function testOnAfterSwapRevertsWhenCapExceeded() public {
        _mockGetSender(alice);

        // First purchase: 800.
        AfterSwapParams memory params1 = _buildAfterSwapParams(usdc, dai, 800e18, address(router), lbpPool);
        vm.prank(address(vault));
        hook.onAfterSwap(params1);

        // Second purchase: 300 (total would be 1100 > 1000 cap).
        AfterSwapParams memory params2 = _buildAfterSwapParams(usdc, dai, 300e18, address(router), lbpPool);

        vm.expectRevert(
            abi.encodeWithSelector(
                LBPKYCHook.CapExceeded.selector,
                300e18, // requestedAmountRaw (dai is 18 decimals, so raw == scaled18)
                200e18 // remainingAllocationRaw
            )
        );

        vm.prank(address(vault));
        hook.onAfterSwap(params2);
    }

    function testOnAfterSwapIgnoresNonCappedTokenOut() public {
        _mockGetSender(alice);

        // tokenOut is usdc (reserve), not dai (capped) — should not track.
        AfterSwapParams memory params = _buildAfterSwapParams(dai, usdc, 5000e18, address(router), lbpPool);

        vm.prank(address(vault));
        (bool success, ) = hook.onAfterSwap(params);

        assertTrue(success);
        assertEq(hook.remainingAllocation(alice), MAX_CAP_RAW);
    }

    function testOnAfterSwapCapsArePerUser() public {
        // Alice buys 600.
        _mockGetSender(alice);
        AfterSwapParams memory paramsAlice = _buildAfterSwapParams(usdc, dai, 600e18, address(router), lbpPool);
        vm.prank(address(vault));
        hook.onAfterSwap(paramsAlice);

        // Bob buys 800 — fine, his own cap.
        _mockGetSender(bob);
        AfterSwapParams memory paramsBob = _buildAfterSwapParams(usdc, dai, 800e18, address(router), lbpPool);
        vm.prank(address(vault));
        hook.onAfterSwap(paramsBob);

        assertEq(hook.remainingAllocation(alice), 400e18);
        assertEq(hook.remainingAllocation(bob), 200e18);
    }

    function testOnAfterSwapEmitsCappedTokensBought() public {
        uint256 buyAmount = 100e18;
        _mockGetSender(alice);

        AfterSwapParams memory params = _buildAfterSwapParams(usdc, dai, buyAmount, address(router), lbpPool);

        vm.expectEmit();
        emit LBPKYCHook.CappedTokensBought(alice, dai, buyAmount);

        vm.prank(address(vault));
        hook.onAfterSwap(params);
    }

    function testOnAfterSwapRouterNotTrusted() public {
        address untrustedRouter = makeAddr("untrustedRouter");

        AfterSwapParams memory params = _buildAfterSwapParams(usdc, dai, 100e18, untrustedRouter, lbpPool);

        vm.expectRevert(abi.encodeWithSelector(LBPKYCHook.RouterNotTrusted.selector, untrustedRouter));

        vm.prank(address(vault));
        hook.onAfterSwap(params);
    }

    function testOnAfterSwapDoesNotReturnAdjustedAmount() public {
        uint256 buyAmount = 100e18;
        uint256 amountCalculatedRaw = 99e18;
        _mockGetSender(alice);

        AfterSwapParams memory params = _buildAfterSwapParams(usdc, dai, buyAmount, address(router), lbpPool);
        params.amountCalculatedRaw = amountCalculatedRaw;

        vm.prank(address(vault));
        (bool success, uint256 returnedAmount) = hook.onAfterSwap(params);

        assertTrue(success);
        assertEq(returnedAmount, amountCalculatedRaw, "Hook should pass through amountCalculatedRaw unchanged");
    }

    function testOnAfterSwapSellingCappedTokenDoesNotReduceAllocation() public {
        _mockGetSender(alice);

        // Alice buys 500 of the capped token.
        AfterSwapParams memory buyParams = _buildAfterSwapParams(usdc, dai, 500e18, address(router), lbpPool);
        vm.prank(address(vault));
        hook.onAfterSwap(buyParams);

        assertEq(hook.remainingAllocation(alice), 500e18);

        // Alice sells capped token back (tokenIn=dai, tokenOut=usdc) — should NOT change allocation.
        AfterSwapParams memory sellParams = _buildAfterSwapParams(dai, usdc, 500e18, address(router), lbpPool);
        vm.prank(address(vault));
        hook.onAfterSwap(sellParams);

        assertEq(hook.remainingAllocation(alice), 500e18, "Selling should not reduce tracked allocation");
    }

    function testRemainingAllocationFreshUser() public view {
        assertEq(hook.remainingAllocation(alice), MAX_CAP_RAW);
    }

    function testRemainingAllocationNoCap() public view {
        // When cap is type(uint256).max, remainingAllocation should return max - 0 = max.
        assertEq(hookNoCap.remainingAllocation(alice), type(uint256).max);
    }

    function testDomainSeparatorsAreDifferentPerHook() public view {
        // Two hook instances should have different domain separators (different verifyingContract).
        assertNotEq(hook.domainSeparator(), hookNoCap.domainSeparator());
    }

    /***************************************************************************
                                Signing Helpers
    ***************************************************************************/

    function _signKYC(
        uint256 pk,
        LBPKYCHook targetHook,
        address user,
        address poolAddr,
        uint256 deadline
    ) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(abi.encode(targetHook.KYC_AUTHORIZATION_TYPEHASH(), user, poolAddr, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", targetHook.domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }

    function _encodeUserData(uint256 deadline, bytes memory signature) internal pure returns (bytes memory) {
        return abi.encode(deadline, signature);
    }

    /***************************************************************************
                              Mock / Builder Helpers
    ***************************************************************************/

    function _mockGetSender(address sender) internal {
        vm.mockCall(address(router), abi.encodeWithSelector(ISenderGuard.getSender.selector), abi.encode(sender));
    }

    function _buildSwapParams(address routerAddr, bytes memory userData) internal pure returns (PoolSwapParams memory) {
        uint256[] memory balances = new uint256[](2);
        balances[0] = 1000e18;
        balances[1] = 1000e18;

        return
            PoolSwapParams({
                kind: SwapKind.EXACT_IN,
                amountGivenScaled18: 100e18,
                balancesScaled18: balances,
                indexIn: 0,
                indexOut: 1,
                router: routerAddr,
                userData: userData
            });
    }

    function _buildAfterSwapParams(
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 amountOutScaled18,
        address routerAddr,
        address poolAddr
    ) internal pure returns (AfterSwapParams memory) {
        return
            AfterSwapParams({
                kind: SwapKind.EXACT_IN,
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                amountInScaled18: 100e18,
                amountOutScaled18: amountOutScaled18,
                tokenInBalanceScaled18: 1000e18,
                tokenOutBalanceScaled18: 1000e18,
                amountCalculatedScaled18: amountOutScaled18,
                amountCalculatedRaw: amountOutScaled18,
                router: routerAddr,
                pool: poolAddr,
                userData: bytes("")
            });
    }
}
