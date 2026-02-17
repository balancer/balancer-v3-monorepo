// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { ILBPKYCHook } from "@balancer-labs/v3-interfaces/contracts/pool-hooks/ILBPKYCHook.sol";
import { ISenderGuard } from "@balancer-labs/v3-interfaces/contracts/vault/ISenderGuard.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";

import { LBPKYCHook } from "../../contracts/LBPKYCHook.sol";

contract LBPKYCHookTest is BaseVaultTest {
    // Cap for the 18-decimal token (dai): 1000 tokens.
    uint256 internal constant MAX_CAP_RAW_18DEC = 1000e18;
    // Cap for the 6-decimal token (usdc6Decimals): 1000 tokens.
    uint256 internal constant MAX_CAP_RAW_6DEC = 1000e6;

    LBPKYCHook internal hook;
    LBPKYCHook internal hookNoCap;
    LBPKYCHook internal hook6Dec;

    uint256 internal signerPk;
    address internal signerAddr;
    address internal lbpPool;

    // `dai` is used as the capped (project) token for 18-decimal tests.
    // `usdc6Decimals` is used as the capped (project) token for 6-decimal tests.
    // `usdc` is used as the reserve token in both cases.

    function setUp() public override {
        super.setUp();

        signerPk = 0xdeadbeef;
        signerAddr = vm.addr(signerPk);
        lbpPool = makeAddr("lbpPool");

        // Hook with cap enabled (18-decimal capped token).
        hook = new LBPKYCHook(IVault(address(vault)), address(router), dai, MAX_CAP_RAW_18DEC, signerAddr);

        // Hook with cap disabled (KYC-only mode): zero capped token, zero cap amount.
        hookNoCap = new LBPKYCHook(IVault(address(vault)), address(router), IERC20(address(0)), 0, signerAddr);

        // Hook with cap enabled (6-decimal capped token).
        hook6Dec = new LBPKYCHook(IVault(address(vault)), address(router), usdc6Decimals, MAX_CAP_RAW_6DEC, signerAddr);

        // Register all hooks so `onlyAuthorizedCaller` passes.
        _registerHook(hook);
        _registerHook(hookNoCap);
        _registerHook(hook6Dec);
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

    /***************************************************************************
                                  Constructor
    ***************************************************************************/

    function testConstructorSetsImmutables() public view {
        assertEq(
            hook.KYC_AUTHORIZATION_TYPEHASH(),
            keccak256("KYCAuthorization(address user,address pool,uint256 deadline)")
        );
        assertNotEq(hook.domainSeparator(), bytes32(0));
    }

    function testConstructorRevertsIfZeroTokenWithNonZeroCap() public {
        vm.expectRevert(ILBPKYCHook.InvalidConfiguration.selector);

        new LBPKYCHook(IVault(address(vault)), address(router), IERC20(address(0)), 1000e18, signerAddr);
    }

    function testConstructorAcceptsZeroTokenWithZeroCap() public {
        // Should not revert.
        LBPKYCHook kycOnly = new LBPKYCHook(IVault(address(vault)), address(router), IERC20(address(0)), 0, signerAddr);

        assertEq(address(kycOnly.getCappedToken()), address(0));
    }

    function testOnRegisterEmitsEvent() public {
        LBPKYCHook newHook = new LBPKYCHook(
            IVault(address(vault)),
            address(router),
            dai,
            MAX_CAP_RAW_18DEC,
            signerAddr
        );
        address newPool = makeAddr("newPool");

        vm.expectEmit();
        emit ILBPKYCHook.LBPKYCHookRegistered(newPool, address(this), dai, MAX_CAP_RAW_18DEC);

        vm.prank(address(vault));
        newHook.onRegister(
            address(this),
            newPool,
            new TokenConfig[](2),
            LiquidityManagement(false, false, false, false)
        );
    }

    function testOnRegisterEmitsEventNoCap() public {
        LBPKYCHook newHook = new LBPKYCHook(IVault(address(vault)), address(router), IERC20(address(0)), 0, signerAddr);
        address newPool = makeAddr("newPool");

        vm.expectEmit();
        emit ILBPKYCHook.LBPKYCHookRegistered(newPool, address(this), IERC20(address(0)), 0);

        vm.prank(address(vault));
        newHook.onRegister(
            address(this),
            newPool,
            new TokenConfig[](2),
            LiquidityManagement(false, false, false, false)
        );
    }

    function testOnRegisterEmitsEvent6Dec() public {
        LBPKYCHook newHook = new LBPKYCHook(
            IVault(address(vault)),
            address(router),
            usdc6Decimals,
            MAX_CAP_RAW_6DEC,
            signerAddr
        );
        address newPool = makeAddr("newPool");

        vm.expectEmit();
        emit ILBPKYCHook.LBPKYCHookRegistered(newPool, address(this), usdc6Decimals, MAX_CAP_RAW_6DEC);

        vm.prank(address(vault));
        newHook.onRegister(
            address(this),
            newPool,
            new TokenConfig[](2),
            LiquidityManagement(false, false, false, false)
        );
    }

    /***************************************************************************
                                    Getters
    ***************************************************************************/

    function testGetTrustedRouter() public view {
        assertEq(hook.getTrustedRouter(), address(router));
    }

    function testGetAuthorizedSigner() public view {
        assertEq(hook.getAuthorizedSigner(), signerAddr);
    }

    function testGetCappedToken() public view {
        assertEq(address(hook.getCappedToken()), address(dai));
        assertEq(address(hookNoCap.getCappedToken()), address(0));
        assertEq(address(hook6Dec.getCappedToken()), address(usdc6Decimals));
    }

    function testGetCurrentCappedTokenTotalForUserFreshUser() public view {
        assertEq(hook.getCappedTokenAllocationUsed(alice), 0);
    }

    function testGetCurrentCappedTokenTotalForUserAfterPurchase() public {
        uint256 buyAmount = 200e18;
        _mockGetSender(alice);

        AfterSwapParams memory params = _buildAfterSwapParams(usdc, dai, buyAmount, address(router), lbpPool);
        vm.prank(address(vault));
        hook.onAfterSwap(params);

        assertEq(hook.getCappedTokenAllocationUsed(alice), buyAmount);
    }

    function testGetCurrentCappedTokenTotalRevertsIfNoCappedToken() public {
        vm.expectRevert(ILBPKYCHook.NoCappedTokenSet.selector);

        hookNoCap.getCappedTokenAllocationUsed(alice);
    }

    function testGetRemainingCappedTokenAllocationRevertsIfNoCappedToken() public {
        vm.expectRevert(ILBPKYCHook.NoCappedTokenSet.selector);

        hookNoCap.getCappedTokenAllocationRemaining(alice);
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

    function testHookFlagsWith6DecCap() public view {
        HookFlags memory flags = hook6Dec.getHookFlags();

        assertTrue(flags.shouldCallBeforeSwap, "shouldCallBeforeSwap should be true");
        assertTrue(flags.shouldCallAfterSwap, "shouldCallAfterSwap should be true");
    }

    /***************************************************************************
                          onBeforeSwap KYC Enforcement
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

        vm.expectRevert(abi.encodeWithSelector(ILBPKYCHook.RouterNotTrusted.selector, untrustedRouter));

        vm.prank(address(vault));
        hook.onBeforeSwap(params, lbpPool);
    }

    function testOnBeforeSwapExpired() public {
        uint256 deadline = block.timestamp - 1;
        _mockGetSender(alice);

        bytes memory sig = _signKYC(signerPk, hook, alice, lbpPool, deadline);
        bytes memory userData = _encodeUserData(deadline, sig);
        PoolSwapParams memory params = _buildSwapParams(address(router), userData);

        vm.expectRevert(ILBPKYCHook.KYCExpired.selector);

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

        vm.expectRevert(abi.encodeWithSelector(ILBPKYCHook.UnauthorizedSigner.selector, bogusAddr));

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
        uint256 deadline = block.timestamp; // exactly now; should pass (<=)
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

    function testOnBeforeSwapWorksOnKYCOnlyHook() public {
        uint256 deadline = block.timestamp + 1 hours;
        _mockGetSender(alice);

        bytes memory sig = _signKYC(signerPk, hookNoCap, alice, lbpPool, deadline);
        bytes memory userData = _encodeUserData(deadline, sig);
        PoolSwapParams memory params = _buildSwapParams(address(router), userData);

        vm.prank(address(vault));
        assertTrue(hookNoCap.onBeforeSwap(params, lbpPool));
    }

    /***************************************************************************
                    onAfterSwap Cap Enforcement (18-decimal)
    ***************************************************************************/

    function testOnAfterSwapTracksAllocation() public {
        uint256 buyAmount = 200e18;
        _mockGetSender(alice);

        AfterSwapParams memory params = _buildAfterSwapParams(usdc, dai, buyAmount, address(router), lbpPool);

        vm.prank(address(vault));
        (bool success, ) = hook.onAfterSwap(params);

        assertTrue(success);
        assertEq(hook.getCappedTokenAllocationRemaining(alice), MAX_CAP_RAW_18DEC - buyAmount);
        assertEq(hook.getCappedTokenAllocationUsed(alice), buyAmount);
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
        assertEq(hook.getCappedTokenAllocationRemaining(alice), 0);
        assertEq(hook.getCappedTokenAllocationUsed(alice), MAX_CAP_RAW_18DEC);
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
                ILBPKYCHook.CapExceeded.selector,
                300e18, // requestedAmountRaw (dai is 18 decimals, so raw == scaled18)
                200e18 // remainingAllocationRaw
            )
        );

        vm.prank(address(vault));
        hook.onAfterSwap(params2);
    }

    function testOnAfterSwapIgnoresNonCappedTokenOut() public {
        _mockGetSender(alice);

        // tokenOut is usdc (reserve), not dai (capped): should not track.
        AfterSwapParams memory params = _buildAfterSwapParams(dai, usdc, 5000e18, address(router), lbpPool);

        vm.prank(address(vault));
        (bool success, ) = hook.onAfterSwap(params);

        assertTrue(success);
        assertEq(hook.getCappedTokenAllocationRemaining(alice), MAX_CAP_RAW_18DEC);
    }

    function testOnAfterSwapCapsArePerUser() public {
        // Alice buys 600.
        _mockGetSender(alice);
        AfterSwapParams memory paramsAlice = _buildAfterSwapParams(usdc, dai, 600e18, address(router), lbpPool);
        vm.prank(address(vault));
        hook.onAfterSwap(paramsAlice);

        // Bob buys 800 (his own cap)
        _mockGetSender(bob);
        AfterSwapParams memory paramsBob = _buildAfterSwapParams(usdc, dai, 800e18, address(router), lbpPool);
        vm.prank(address(vault));
        hook.onAfterSwap(paramsBob);

        assertEq(hook.getCappedTokenAllocationRemaining(alice), 400e18);
        assertEq(hook.getCappedTokenAllocationRemaining(bob), 200e18);
        assertEq(hook.getCappedTokenAllocationUsed(alice), 600e18);
        assertEq(hook.getCappedTokenAllocationUsed(bob), 800e18);
    }

    function testOnAfterSwapEmitsCappedTokensBought() public {
        uint256 buyAmount = 100e18;
        _mockGetSender(alice);

        AfterSwapParams memory params = _buildAfterSwapParams(usdc, dai, buyAmount, address(router), lbpPool);

        vm.expectEmit();
        emit ILBPKYCHook.CappedTokensBought(alice, dai, buyAmount);

        vm.prank(address(vault));
        hook.onAfterSwap(params);
    }

    function testOnAfterSwapRouterNotTrusted() public {
        address untrustedRouter = makeAddr("untrustedRouter");

        AfterSwapParams memory params = _buildAfterSwapParams(usdc, dai, 100e18, untrustedRouter, lbpPool);

        vm.expectRevert(abi.encodeWithSelector(ILBPKYCHook.RouterNotTrusted.selector, untrustedRouter));

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

        assertEq(hook.getCappedTokenAllocationRemaining(alice), 500e18);

        // Alice sells capped token back (tokenIn=dai, tokenOut=usdc): should NOT change allocation.
        AfterSwapParams memory sellParams = _buildAfterSwapParams(dai, usdc, 500e18, address(router), lbpPool);
        vm.prank(address(vault));
        hook.onAfterSwap(sellParams);

        assertEq(hook.getCappedTokenAllocationRemaining(alice), 500e18, "Selling should not reduce tracked allocation");
    }

    /***************************************************************************
              onAfterSwap Cap Enforcement (6-decimal capped token)
    ***************************************************************************/

    function testOnAfterSwap6DecTracksAllocation() public {
        // Buy 200 tokens. Vault passes scaled18; remaining allocation returns raw (6 decimals).
        uint256 buyAmountScaled18 = 200e18;
        uint256 expectedRemainingRaw = MAX_CAP_RAW_6DEC - 200e6;
        _mockGetSender(alice);

        AfterSwapParams memory params = _buildAfterSwapParams(
            usdc,
            usdc6Decimals,
            buyAmountScaled18,
            address(router),
            lbpPool
        );

        vm.prank(address(vault));
        (bool success, ) = hook6Dec.onAfterSwap(params);

        assertTrue(success);
        assertEq(hook6Dec.getCappedTokenAllocationRemaining(alice), expectedRemainingRaw);
        assertEq(hook6Dec.getCappedTokenAllocationUsed(alice), 200e6);
    }

    function testOnAfterSwap6DecEmitsRawAmount() public {
        // Buy 123.456789 tokens: scaled18 = 123.456789e18, raw 6-dec = 123456789 = 123.456789e6.
        uint256 buyAmountScaled18 = 123_456789e12; // 123.456789e18
        uint256 expectedRaw = 123_456789; // 123.456789 in 6 decimals
        _mockGetSender(alice);

        AfterSwapParams memory params = _buildAfterSwapParams(
            usdc,
            usdc6Decimals,
            buyAmountScaled18,
            address(router),
            lbpPool
        );

        vm.expectEmit();
        emit ILBPKYCHook.CappedTokensBought(alice, usdc6Decimals, expectedRaw);

        vm.prank(address(vault));
        hook6Dec.onAfterSwap(params);
    }

    function testOnAfterSwap6DecCapExceededShowsRawAmounts() public {
        _mockGetSender(alice);

        // First purchase: 800 tokens (scaled18 = 800e18).
        AfterSwapParams memory params1 = _buildAfterSwapParams(usdc, usdc6Decimals, 800e18, address(router), lbpPool);
        vm.prank(address(vault));
        hook6Dec.onAfterSwap(params1);

        // Second purchase: 300 tokens (scaled18 = 300e18). Total would be 1100 > 1000 cap.
        AfterSwapParams memory params2 = _buildAfterSwapParams(usdc, usdc6Decimals, 300e18, address(router), lbpPool);

        vm.expectRevert(
            abi.encodeWithSelector(
                ILBPKYCHook.CapExceeded.selector,
                300e6, // requestedAmountRaw (6 decimals)
                200e6 // remainingAllocationRaw (6 decimals)
            )
        );

        vm.prank(address(vault));
        hook6Dec.onAfterSwap(params2);
    }

    function testOnAfterSwap6DecMultiplePurchasesUpToCap() public {
        _mockGetSender(alice);

        // First purchase: 600 tokens.
        AfterSwapParams memory params1 = _buildAfterSwapParams(usdc, usdc6Decimals, 600e18, address(router), lbpPool);
        vm.prank(address(vault));
        hook6Dec.onAfterSwap(params1);

        // Second purchase: 400 tokens (total = 1000 = cap).
        AfterSwapParams memory params2 = _buildAfterSwapParams(usdc, usdc6Decimals, 400e18, address(router), lbpPool);
        vm.prank(address(vault));
        (bool success, ) = hook6Dec.onAfterSwap(params2);

        assertTrue(success);
        assertEq(hook6Dec.getCappedTokenAllocationRemaining(alice), 0);
        assertEq(hook6Dec.getCappedTokenAllocationUsed(alice), MAX_CAP_RAW_6DEC);
    }

    function testOnAfterSwap6DecRemainingAllocationFreshUser() public view {
        assertEq(hook6Dec.getCappedTokenAllocationRemaining(alice), MAX_CAP_RAW_6DEC);
    }

    /***************************************************************************
                          remainingAllocation / misc
    ***************************************************************************/

    function testRemainingAllocationFreshUser() public view {
        assertEq(hook.getCappedTokenAllocationRemaining(alice), MAX_CAP_RAW_18DEC);
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
