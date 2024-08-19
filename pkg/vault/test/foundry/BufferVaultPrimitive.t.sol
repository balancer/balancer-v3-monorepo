// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IVaultEvents } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultEvents.sol";
import { IVaultMain } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IBatchRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IBatchRouter.sol";
import {
    BufferWrapOrUnwrapParams,
    SwapKind,
    WrappingDirection
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { ERC4626TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC4626TestToken.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract BufferVaultPrimitiveTest is BaseVaultTest {
    using FixedPoint for uint256;

    ERC4626TestToken internal waDAI;
    ERC4626TestToken internal waUSDC;

    uint256 private constant _userAmount = 10e6 * 1e18;
    uint256 private constant _wrapAmount = _userAmount / 100;

    uint256 private constant MIN_WRAP_AMOUNT = 1e3;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        waDAI = new ERC4626TestToken(dai, "Wrapped aDAI", "waDAI", 18);
        vm.label(address(waDAI), "waDAI");

        // "USDC" is deliberately 18 decimals to test one thing at a time.
        waUSDC = new ERC4626TestToken(usdc, "Wrapped aUSDC", "waUSDC", 18);
        vm.label(address(waUSDC), "waUSDC");

        // Authorizes user "admin" to pause/unpause vault's buffer.
        authorizer.grantRole(vault.getActionId(IVaultAdmin.pauseVaultBuffers.selector), admin);
        authorizer.grantRole(vault.getActionId(IVaultAdmin.unpauseVaultBuffers.selector), admin);
        // Authorizes router to call removeLiquidityFromBuffer (trusted router).
        authorizer.grantRole(vault.getActionId(IVaultAdmin.removeLiquidityFromBuffer.selector), address(router));

        initializeLp();
    }

    function initializeLp() private {
        // Create and fund buffer pools
        vm.startPrank(lp);

        dai.mint(lp, _userAmount);
        dai.approve(address(waDAI), _userAmount);
        waDAI.deposit(_userAmount, lp);

        usdc.mint(lp, _userAmount);
        usdc.approve(address(waUSDC), _userAmount);
        waUSDC.deposit(_userAmount, lp);

        // Minting wrong token to wrapped token contracts, to test changing the asset.
        dai.mint(address(waUSDC), _userAmount);
        usdc.mint(address(waDAI), _userAmount);

        waDAI.approve(address(permit2), MAX_UINT256);
        permit2.approve(address(waDAI), address(router), type(uint160).max, type(uint48).max);
        permit2.approve(address(waDAI), address(batchRouter), type(uint160).max, type(uint48).max);
        waUSDC.approve(address(permit2), MAX_UINT256);
        permit2.approve(address(waUSDC), address(router), type(uint160).max, type(uint48).max);
        permit2.approve(address(waUSDC), address(batchRouter), type(uint160).max, type(uint48).max);
        vm.stopPrank();
    }

    /********************************************************************************
                                        Asset
    ********************************************************************************/
    function testChangeAssetOfWrappedTokenAddLiquidityToBuffer() public {
        // Change Asset to correct asset.
        waDAI.setAsset(dai);

        vm.prank(lp);
        router.initializeBuffer(IERC4626(address(waDAI)), _wrapAmount, _wrapAmount);

        // Change Asset to the wrong asset.
        waDAI.setAsset(usdc);

        vm.prank(lp);
        vm.expectRevert(
            abi.encodeWithSelector(IVaultErrors.WrongUnderlyingToken.selector, address(waDAI), address(usdc))
        );
        router.addLiquidityToBuffer(IERC4626(address(waDAI)), _wrapAmount, _wrapAmount);
    }

    function testChangeAssetOfWrappedTokenRemoveLiquidityFromBuffer() public {
        // Change Asset to correct asset.
        waDAI.setAsset(dai);

        vm.prank(lp);
        uint256 lpShares = router.initializeBuffer(IERC4626(address(waDAI)), _wrapAmount, _wrapAmount);

        // Change Asset to the wrong asset.
        waDAI.setAsset(usdc);

        // Does not revert: remove liquidity doesn't check whether the asset matches the registered one in order to
        // avoid external calls. You can always exit the buffer, even if the wrapper is corrupt and updated its asset.
        vm.prank(lp);
        vault.removeLiquidityFromBuffer(IERC4626(address(waDAI)), lpShares);
    }

    function testChangeAssetOfWrappedTokenWrapUnwrap() public {
        // Change Asset to correct asset.
        waDAI.setAsset(dai);

        // Wrap token should pass, since there's no liquidity in the buffer.
        IBatchRouter.SwapPathExactAmountIn[] memory paths = _exactInWrapUnwrapPath(
            _wrapAmount,
            0,
            usdc,
            IERC20(address(waDAI)),
            IERC20(address(waDAI))
        );

        vm.prank(lp);
        router.initializeBuffer(IERC4626(address(waDAI)), _wrapAmount, _wrapAmount);

        // Change Asset to the wrong asset.
        waDAI.setAsset(usdc);

        // Wrap token should fail, since buffer has liquidity.
        vm.prank(lp);
        vm.expectRevert(
            abi.encodeWithSelector(IVaultErrors.WrongUnderlyingToken.selector, address(waDAI), address(usdc))
        );
        batchRouter.swapExactIn(paths, MAX_UINT256, false, bytes(""));
    }

    /********************************************************************************
                                        Deposit
    ********************************************************************************/
    function testDepositInteractionWithERC4626Protocol() public {
        // Initializes the buffer with an amount that's not enough to fulfill the deposit operation, so the vault has
        // to interact with the ERC4626 protocol.
        vm.prank(lp);
        router.initializeBuffer(IERC4626(address(waDAI)), _wrapAmount / 10, _wrapAmount / 10);

        IBatchRouter.SwapPathExactAmountIn[] memory paths = _exactInWrapUnwrapPath(
            _wrapAmount,
            0,
            dai,
            IERC20(address(waDAI)),
            IERC20(address(waDAI))
        );

        uint256 lpUnderlyingBalanceBefore = dai.balanceOf(lp);
        uint256 lpWrappedBalanceBefore = IERC20(address(waDAI)).balanceOf(lp);

        vm.prank(lp);
        batchRouter.swapExactIn(paths, MAX_UINT256, false, bytes(""));

        uint256 lpUnderlyingBalanceAfter = dai.balanceOf(lp);
        uint256 lpWrappedBalanceAfter = IERC20(address(waDAI)).balanceOf(lp);

        assertEq(
            lpUnderlyingBalanceAfter,
            lpUnderlyingBalanceBefore - _wrapAmount,
            "LP balance of underlying token is wrong"
        );
        assertEq(
            lpWrappedBalanceAfter,
            lpWrappedBalanceBefore + waDAI.previewDeposit(_wrapAmount),
            "LP balance of wrapped token is wrong"
        );
    }

    function testDepositWithBufferLiquidity() public {
        // Initializes the buffer with an amount that's enough to fulfill the deposit operation without interacting
        // with the ERC4626 protocol.
        vm.prank(lp);
        router.initializeBuffer(IERC4626(address(waDAI)), 2 * _wrapAmount, 2 * _wrapAmount);

        IBatchRouter.SwapPathExactAmountIn[] memory paths = _exactInWrapUnwrapPath(
            _wrapAmount,
            0,
            dai,
            IERC20(address(waDAI)),
            IERC20(address(waDAI))
        );

        uint256 lpUnderlyingBalanceBefore = dai.balanceOf(lp);
        uint256 lpWrappedBalanceBefore = IERC20(address(waDAI)).balanceOf(lp);

        vm.prank(lp);
        batchRouter.swapExactIn(paths, MAX_UINT256, false, bytes(""));

        uint256 lpUnderlyingBalanceAfter = dai.balanceOf(lp);
        uint256 lpWrappedBalanceAfter = IERC20(address(waDAI)).balanceOf(lp);

        assertEq(
            lpUnderlyingBalanceAfter,
            lpUnderlyingBalanceBefore - _wrapAmount,
            "LP balance of underlying token is wrong"
        );
        assertEq(
            lpWrappedBalanceAfter,
            lpWrappedBalanceBefore + waDAI.previewDeposit(_wrapAmount),
            "LP balance of wrapped token is wrong"
        );
    }

    /**
     * @notice Tests protection against potential denial-of-service (DoS) attacks during deposits to an ERC4626 wrapper.
     * @dev A DoS attack can exploit synchronization issues between the vault's _reservesOf variable and its actual
     * balances at the start of a transaction. This can lead to arithmetic errors and incorrect assumptions about
     * balance changes if the reserves are out of sync, which reverts the transaction.
     *
     * Example of a potential DoS attack:
     * 1. The vault initially holds 100 DAI and the rate of DAI to waDAI is 1:1.
     * 2. A frontrunner deposits 50 DAI into the vault. The vault's actual balance increases to 150 DAI, but the
     * _reservesOf variable incorrectly remains at 100 DAI (out of sync).
     * 3. Then, the actual deposit operation is executed, depositing 30 DAI. This operation should decrease the vault's
     * balances by 30 DAI, resulting in an expected balance of 70 DAI, but since the vault has 50 DAI extra, the final
     * balance is 120 DAI.
     * 4. The vault's logic, based on the outdated _reservesOf 100 DAI, mistakenly interprets the situation as an
     * unwrap operation becsause the amount of DAI increased from 100 to 120 DAI instead of decreasing from 100 to 70.
     * So, the operation reverts with an arithmetic issue.
     * 5. After the transaction is reverted and DoS attack is complete, the attacker could then call sendTo() and
     * settle() functions to remove their donated tokens from the vault.
     */
    function testDepositDoS() public {
        // Initializes the buffer with an amount that's not possible to fulfill the deposit operation.
        vm.prank(lp);
        router.initializeBuffer(IERC4626(address(waDAI)), _wrapAmount / 10, _wrapAmount / 10);

        uint256 lpUnderlyingBalanceBefore = dai.balanceOf(lp);
        uint256 lpWrappedBalanceBefore = IERC20(address(waDAI)).balanceOf(lp);

        // Approves this test to act as a router and move DAI from lp to vault.
        vm.prank(lp);
        dai.approve(address(this), _wrapAmount);

        (uint256 amountsIn, uint256 amountsOut) = abi.decode(
            vault.unlock(
                abi.encodeWithSelector(
                    BufferVaultPrimitiveTest.erc4626DoSHook.selector,
                    BufferWrapOrUnwrapParams({
                        kind: SwapKind.EXACT_IN,
                        direction: WrappingDirection.WRAP,
                        wrappedToken: IERC4626(address(waDAI)),
                        amountGivenRaw: _wrapAmount,
                        limitRaw: 0,
                        userData: bytes("")
                    }),
                    lp
                )
            ),
            (uint256, uint256)
        );

        uint256 lpUnderlyingBalanceAfter = dai.balanceOf(lp);
        uint256 lpWrappedBalanceAfter = IERC20(address(waDAI)).balanceOf(lp);

        // Check user balances
        assertEq(
            lpUnderlyingBalanceAfter,
            lpUnderlyingBalanceBefore - _wrapAmount,
            "LP balance of underlying token is wrong"
        );
        assertEq(
            lpWrappedBalanceAfter,
            lpWrappedBalanceBefore + waDAI.previewDeposit(_wrapAmount),
            "LP balance of wrapped token is wrong"
        );

        // Check Vault balances
        //  Extra tokens should be adjusted and funds should be absorbed (lost)
    }

    function testDepositMaliciousRouter() public {
        vm.prank(lp);
        router.initializeBuffer(IERC4626(address(waDAI)), _wrapAmount, _wrapAmount);

        // Deposit will not take the underlying tokens, keeping the approval, so the wrapper can use vault approval to
        // drain the whole vault.
        waDAI.setMaliciousWrapper(true);

        uint256 vaultBalance = dai.balanceOf(address(vault));

        // If a wrapper operation takes less tokens than what the user requested, or returns less tokens than the
        // wrapper informs, that quantities must be settled by the router. So, an approval attack is not possible.
        vm.expectRevert(IVaultErrors.BalanceNotSettled.selector);
        vault.unlock(
            abi.encodeWithSelector(
                BufferVaultPrimitiveTest.erc4626MaliciousHook.selector,
                BufferWrapOrUnwrapParams({
                    kind: SwapKind.EXACT_IN,
                    direction: WrappingDirection.WRAP,
                    wrappedToken: IERC4626(address(waDAI)),
                    amountGivenRaw: vaultBalance,
                    limitRaw: 0,
                    userData: bytes("")
                })
            )
        );
    }

    /********************************************************************************
                                        Mint
    ********************************************************************************/
    function testMint() public {
        vm.prank(lp);
        router.initializeBuffer(IERC4626(address(waDAI)), _wrapAmount, _wrapAmount);

        IBatchRouter.SwapPathExactAmountOut[] memory paths = _exactOutWrapUnwrapPath(
            2 * _wrapAmount,
            _wrapAmount,
            dai,
            IERC20(address(waDAI)),
            IERC20(address(waDAI))
        );

        uint256 lpUnderlyingBalanceBefore = dai.balanceOf(lp);
        uint256 lpWrappedBalanceBefore = IERC20(address(waDAI)).balanceOf(lp);

        vm.prank(lp);
        batchRouter.swapExactOut(paths, MAX_UINT256, false, bytes(""));

        uint256 lpUnderlyingBalanceAfter = dai.balanceOf(lp);
        uint256 lpWrappedBalanceAfter = IERC20(address(waDAI)).balanceOf(lp);

        assertEq(
            lpUnderlyingBalanceAfter,
            lpUnderlyingBalanceBefore - waDAI.previewMint(_wrapAmount),
            "LP balance of underlying token is wrong"
        );
        assertEq(lpWrappedBalanceAfter, lpWrappedBalanceBefore + _wrapAmount, "LP balance of wrapped token is wrong");
    }

    function testMintMaliciousRouter() public {
        vm.prank(lp);
        router.initializeBuffer(IERC4626(address(waDAI)), _wrapAmount, _wrapAmount);

        // Deposit will not take the underlying tokens, keeping the approval, so the wrapper can use vault approval to
        // drain the whole vault.
        waDAI.setMaliciousWrapper(true);

        vault.unlock(
            abi.encodeWithSelector(
                BufferVaultPrimitiveTest.erc4626MaliciousHook.selector,
                BufferWrapOrUnwrapParams({
                    kind: SwapKind.EXACT_OUT,
                    direction: WrappingDirection.WRAP,
                    wrappedToken: IERC4626(address(waDAI)),
                    amountGivenRaw: MIN_WRAP_AMOUNT,
                    limitRaw: MAX_UINT128,
                    userData: bytes("")
                })
            )
        );

        // After a wrap operation, even if the erc4626 token didn't take all the assets it was supposed to deposit,
        // the allowance should be 0 to avoid a malicious wrapper from draining the underlying balance of the vault.
        assertTrue(dai.allowance(address(vault), address(waDAI)) == 0, "Wrong allowance");
    }

    /********************************************************************************
                                        Redeem
    ********************************************************************************/
    function testRedeem() public {
        vm.prank(lp);
        router.initializeBuffer(IERC4626(address(waDAI)), _wrapAmount, _wrapAmount);

        IBatchRouter.SwapPathExactAmountIn[] memory paths = _exactInWrapUnwrapPath(
            _wrapAmount,
            0,
            IERC20(address(waDAI)),
            dai,
            IERC20(address(waDAI))
        );

        uint256 lpUnderlyingBalanceBefore = dai.balanceOf(lp);
        uint256 lpWrappedBalanceBefore = IERC20(address(waDAI)).balanceOf(lp);

        vm.prank(lp);
        batchRouter.swapExactIn(paths, MAX_UINT256, false, bytes(""));

        uint256 lpUnderlyingBalanceAfter = dai.balanceOf(lp);
        uint256 lpWrappedBalanceAfter = IERC20(address(waDAI)).balanceOf(lp);

        assertEq(
            lpUnderlyingBalanceAfter,
            lpUnderlyingBalanceBefore + _wrapAmount,
            "LP balance of underlying token is wrong"
        );
        assertEq(
            lpWrappedBalanceAfter,
            lpWrappedBalanceBefore - waDAI.previewRedeem(_wrapAmount),
            "LP balance of wrapped token is wrong"
        );
    }

    /********************************************************************************
                                        Withdraw
    ********************************************************************************/
    function testWithdraw() public {
        vm.prank(lp);
        router.initializeBuffer(IERC4626(address(waDAI)), _wrapAmount, _wrapAmount);

        IBatchRouter.SwapPathExactAmountOut[] memory paths = _exactOutWrapUnwrapPath(
            2 * _wrapAmount,
            _wrapAmount,
            IERC20(address(waDAI)),
            dai,
            IERC20(address(waDAI))
        );

        uint256 lpUnderlyingBalanceBefore = dai.balanceOf(lp);
        uint256 lpWrappedBalanceBefore = IERC20(address(waDAI)).balanceOf(lp);

        vm.prank(lp);
        batchRouter.swapExactOut(paths, MAX_UINT256, false, bytes(""));

        uint256 lpUnderlyingBalanceAfter = dai.balanceOf(lp);
        uint256 lpWrappedBalanceAfter = IERC20(address(waDAI)).balanceOf(lp);

        assertEq(
            lpUnderlyingBalanceAfter,
            lpUnderlyingBalanceBefore + waDAI.previewWithdraw(_wrapAmount),
            "LP balance of underlying token is wrong"
        );
        assertEq(lpWrappedBalanceAfter, lpWrappedBalanceBefore - _wrapAmount, "LP balance of wrapped token is wrong");
    }

    /********************************************************************************
                                Disable Vault Buffers
    ********************************************************************************/
    // Make sure only authorized users can disable/enable vault buffers.
    function testDisableVaultBufferAuthentication() public {
        vm.prank(alice);
        // Should revert, since alice has no rights to disable buffer.
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        IVaultAdmin(address(vault)).pauseVaultBuffers();

        vm.prank(admin);
        // Should pass, since admin has access
        IVaultAdmin(address(vault)).pauseVaultBuffers();

        vm.prank(alice);
        // Should revert, since alice has no rights to enable buffer.
        vm.expectRevert(IAuthentication.SenderNotAllowed.selector);
        IVaultAdmin(address(vault)).unpauseVaultBuffers();

        vm.prank(admin);
        // Should pass, since admin has access.
        IVaultAdmin(address(vault)).unpauseVaultBuffers();
    }

    function testDisableVaultBuffer() public {
        vm.prank(lp);
        router.initializeBuffer(IERC4626(address(waDAI)), _wrapAmount, _wrapAmount);

        vm.prank(admin);
        IVaultAdmin(address(vault)).pauseVaultBuffers();

        IBatchRouter.SwapPathExactAmountIn[] memory paths = _exactInWrapUnwrapPath(
            _wrapAmount,
            0,
            dai,
            IERC20(address(waDAI)),
            IERC20(address(waDAI))
        );

        // Wrap/unwrap, add and remove liquidity should fail, since vault buffers are disabled.
        vm.startPrank(lp);

        vm.expectRevert(IVaultErrors.VaultBuffersArePaused.selector);
        batchRouter.swapExactIn(paths, MAX_UINT256, false, bytes(""));

        vm.expectRevert(IVaultErrors.VaultBuffersArePaused.selector);
        router.addLiquidityToBuffer(IERC4626(address(waDAI)), _wrapAmount, _wrapAmount);

        // Remove liquidity is supposed to pass even with buffers paused, so revert is not expected.
        vault.removeLiquidityFromBuffer(IERC4626(address(waDAI)), _wrapAmount);

        vm.stopPrank();

        vm.prank(admin);
        IVaultAdmin(address(vault)).unpauseVaultBuffers();

        // Deposit should pass, since vault buffers are enabled.
        vm.prank(lp);
        batchRouter.swapExactIn(paths, MAX_UINT256, false, bytes(""));
    }

    /********************************************************************************
                          Add/Remove Liquidity from Buffers
    ********************************************************************************/

    function testAddLiquidityToBuffer() public {
        vm.prank(lp);
        router.initializeBuffer(waDAI, 1e18, 1e18);

        BufferAndLPBalances memory beforeBalances = _measureBuffer();

        uint256 underlyingAmountIn = _wrapAmount;
        uint256 wrappedAmountIn = _wrapAmount.mulDown(2e18);

        uint256 lpSharesBeforeAdd = vault.getBufferOwnerShares(waDAI, lp);
        vm.prank(lp);
        uint256 lpSharesAdded = router.addLiquidityToBuffer(waDAI, underlyingAmountIn, wrappedAmountIn);

        BufferAndLPBalances memory afterBalances = _measureBuffer();

        assertEq(
            afterBalances.buffer.dai,
            beforeBalances.buffer.dai + underlyingAmountIn,
            "Buffer DAI balance is wrong"
        );
        assertEq(
            afterBalances.buffer.waDai,
            beforeBalances.buffer.waDai + wrappedAmountIn,
            "Buffer waDAI balance is wrong"
        );

        assertEq(afterBalances.vault.dai, beforeBalances.vault.dai + underlyingAmountIn, "Vault DAI balance is wrong");
        assertEq(
            afterBalances.vault.waDai,
            beforeBalances.vault.waDai + wrappedAmountIn,
            "Vault waDAI balance is wrong"
        );

        assertEq(
            afterBalances.vaultReserves.dai,
            beforeBalances.vaultReserves.dai + underlyingAmountIn,
            "Vault Reserve DAI balance is wrong"
        );
        assertEq(
            afterBalances.vaultReserves.waDai,
            beforeBalances.vaultReserves.waDai + wrappedAmountIn,
            "Vault Reserve waDAI balance is wrong"
        );

        assertEq(afterBalances.lp.dai, beforeBalances.lp.dai - underlyingAmountIn, "LP DAI balance is wrong");
        assertEq(afterBalances.lp.waDai, beforeBalances.lp.waDai - wrappedAmountIn, "LP waDAI balance is wrong");

        assertEq(
            lpSharesBeforeAdd + lpSharesAdded,
            vault.getBufferOwnerShares(IERC4626(address(waDAI)), lp),
            "LP Buffer shares is wrong"
        );
        assertEq(lpSharesAdded, underlyingAmountIn + waDAI.convertToAssets(wrappedAmountIn), "Issued shares is wrong");
    }

    function testRemoveLiquidityFromBuffer() public {
        uint256 underlyingAmountIn = _wrapAmount;
        uint256 wrappedAmountIn = _wrapAmount.mulDown(2e18);

        vm.prank(lp);
        uint256 lpShares = router.initializeBuffer(waDAI, underlyingAmountIn, wrappedAmountIn);

        BufferAndLPBalances memory beforeBalances = _measureBuffer();

        vm.expectEmit();
        emit IVaultEvents.BufferSharesBurned(IERC4626(waDAI), lp, lpShares);

        vm.prank(lp);
        (uint256 underlyingRemoved, uint256 wrappedRemoved) = vault.removeLiquidityFromBuffer(waDAI, lpShares);

        // The underlying and wrapped removed are not exactly the same as amountsIn, because part of the first deposit
        // is kept to don't deplete the buffer and these shares (MIN_BPT) are "burned". The remove liquidity operation
        // is proportional to buffer balances, so the amount of burned shares must be discounted proportionally from
        // underlying and wrapped.
        assertEq(
            underlyingRemoved,
            underlyingAmountIn - MIN_BPT.mulUp(underlyingAmountIn).divUp(underlyingAmountIn + wrappedAmountIn),
            "Underlying removed is wrong"
        );
        assertEq(
            wrappedRemoved,
            wrappedAmountIn - MIN_BPT.mulUp(wrappedAmountIn).divUp(underlyingAmountIn + wrappedAmountIn),
            "Wrapped removed is wrong"
        );

        BufferAndLPBalances memory afterBalances = _measureBuffer();

        assertEq(
            afterBalances.buffer.dai,
            beforeBalances.buffer.dai - underlyingRemoved,
            "Buffer DAI balance is wrong"
        );
        assertEq(
            afterBalances.buffer.waDai,
            beforeBalances.buffer.waDai - wrappedRemoved,
            "Buffer waDAI balance is wrong"
        );

        assertEq(afterBalances.vault.dai, beforeBalances.vault.dai - underlyingRemoved, "Vault DAI balance is wrong");
        assertEq(
            afterBalances.vault.waDai,
            beforeBalances.vault.waDai - wrappedRemoved,
            "Vault waDAI balance is wrong"
        );

        assertEq(
            afterBalances.vaultReserves.dai,
            beforeBalances.vaultReserves.dai - underlyingRemoved,
            "Vault Reserve DAI balance is wrong"
        );
        assertEq(
            afterBalances.vaultReserves.waDai,
            beforeBalances.vaultReserves.waDai - wrappedRemoved,
            "Vault Reserve waDAI balance is wrong"
        );

        assertEq(afterBalances.lp.dai, beforeBalances.lp.dai + underlyingRemoved, "LP DAI balance is wrong");
        assertEq(afterBalances.lp.waDai, beforeBalances.lp.waDai + wrappedRemoved, "LP waDAI balance is wrong");

        assertEq(vault.getBufferOwnerShares(IERC4626(address(waDAI)), lp), 0, "LP Buffer shares is wrong");
        // If math has rounding issues, the rounding occurs in favor of the vault with a max of 1 wei error.
        assertApproxEqAbs(
            lpShares,
            underlyingRemoved + waDAI.convertToAssets(wrappedRemoved),
            1,
            "Removed assets are wrong"
        );
    }

    struct BufferTokenBalances {
        uint256 waDai;
        uint256 dai;
    }

    struct BufferAndLPBalances {
        BufferTokenBalances lp;
        BufferTokenBalances buffer;
        BufferTokenBalances vault;
        BufferTokenBalances vaultReserves;
    }

    function _measureBuffer() private view returns (BufferAndLPBalances memory vars) {
        vars.lp.dai = dai.balanceOf(lp);
        vars.lp.waDai = waDAI.balanceOf(lp);

        (vars.buffer.dai, vars.buffer.waDai) = vault.getBufferBalance(IERC4626(address(waDAI)));

        vars.vault.dai = dai.balanceOf(address(vault));
        vars.vault.waDai = waDAI.balanceOf(address(vault));

        vars.vaultReserves.dai = vault.getReservesOf(dai);
        vars.vaultReserves.waDai = vault.getReservesOf(IERC20(address(waDAI)));
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

    function _exactOutWrapUnwrapPath(
        uint256 maxAmountIn,
        uint256 exactAmountOut,
        IERC20 tokenFrom,
        IERC20 tokenTo,
        IERC20 wrappedToken
    ) private pure returns (IBatchRouter.SwapPathExactAmountOut[] memory paths) {
        IBatchRouter.SwapPathStep[] memory steps = new IBatchRouter.SwapPathStep[](1);
        paths = new IBatchRouter.SwapPathExactAmountOut[](1);

        steps[0] = IBatchRouter.SwapPathStep({ pool: address(wrappedToken), tokenOut: tokenTo, isBuffer: true });

        paths[0] = IBatchRouter.SwapPathExactAmountOut({
            tokenIn: tokenFrom,
            steps: steps,
            maxAmountIn: maxAmountIn,
            exactAmountOut: exactAmountOut
        });
    }

    /// @notice Hook used to create a vault approval using a malicious erc4626 and drain the vault.
    function erc4626MaliciousHook(BufferWrapOrUnwrapParams memory params) external {
        (, uint256 amountIn, uint256 amountOut) = vault.erc4626BufferWrapOrUnwrap(params);
        if (params.kind == SwapKind.EXACT_OUT) {
            // When the wrap is EXACT_OUT, a minimum amount of tokens must be wrapped. so, balances need to be settled
            // at the end to not revert the transaction and keep an approval to remove underlying tokens from the
            // vault.
            dai.mint(address(this), amountIn);
            dai.transfer(address(vault), amountIn);
            vault.settle(dai, amountIn);
            vault.sendTo(IERC20(address(waDAI)), address(this), amountOut);
        }
    }

    /// @notice Hook used to interact with ERC4626 wrap/unwrap primitive of the vault.
    function erc4626DoSHook(
        BufferWrapOrUnwrapParams memory params,
        address sender
    ) external returns (uint256 amountIn, uint256 amountOut) {
        IERC20 underlyingToken = IERC20(params.wrappedToken.asset());
        IERC20 wrappedToken = IERC20(address(params.wrappedToken));

        // Transfer tokens to the vault and settle, since vault needs to have enough tokens in the reserves to
        // wrap/unwrap.
        if (params.direction == WrappingDirection.WRAP) {
            // Since we're wrapping, we need to transfer underlying tokens to the vault, so it can be wrapped.
            if (params.kind == SwapKind.EXACT_IN) {
                underlyingToken.transferFrom(sender, address(vault), params.amountGivenRaw);
                vault.settle(underlyingToken, params.amountGivenRaw);
            } else {
                underlyingToken.transferFrom(sender, address(vault), params.limitRaw);
                vault.settle(underlyingToken, params.limitRaw);
            }

            // Donate more funds to the vault then the amount that will be deposited, so the vault can think that it's
            // an unwrap because the reserves of underlying tokens increased after the wrap operation. Don't settle, or
            // else the vault will measure the difference of underlying reserves correctly.
            vm.prank(alice);
            dai.transfer(address(vault), _wrapAmount + 10);
        } else {
            if (params.kind == SwapKind.EXACT_IN) {
                wrappedToken.transferFrom(sender, address(vault), params.amountGivenRaw);
                vault.settle(wrappedToken, params.amountGivenRaw);
            } else {
                wrappedToken.transferFrom(sender, address(vault), params.limitRaw);
                vault.settle(wrappedToken, params.limitRaw);
            }
        }

        (, amountIn, amountOut) = vault.erc4626BufferWrapOrUnwrap(params);

        // Settle balances.
        if (params.direction == WrappingDirection.WRAP) {
            if (params.kind == SwapKind.EXACT_OUT) {
                vault.sendTo(underlyingToken, sender, params.limitRaw - amountIn);
            }
            vault.sendTo(wrappedToken, sender, amountOut);
        } else {
            if (params.kind == SwapKind.EXACT_OUT) {
                vault.sendTo(wrappedToken, sender, params.limitRaw - amountIn);
            }
            vault.sendTo(underlyingToken, sender, amountOut);
        }
    }
}
