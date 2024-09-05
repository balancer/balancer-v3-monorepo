// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { ERC4626TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC4626TestToken.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

/**
 * @notice Test protection against denial-of-service (DoS) attacks during interactions with an ERC4626 wrapper.
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
contract BufferDoSProtectionTest is BaseVaultTest {
    using FixedPoint for uint256;

    uint256 private constant _userAmount = 10e6 * 1e18;
    uint256 private constant _wrapAmount = _userAmount / 100;

    function setUp() public virtual override {
        BaseVaultTest.setUp();
        initializeLp();
    }

    function initializeLp() private {
        // Create and fund buffer pools
        vm.startPrank(lp);
        // The test contract acts as the router and does not use permit2, so approve transfers to the router directly.
        dai.approve(address(this), MAX_UINT256);
        waDAI.approve(address(this), MAX_UINT256);
        vm.stopPrank();
    }

    function testDepositDoS() public {
        // Deposit is an EXACT_IN operation, since it's a wrap where we specify the underlying amount in.
        _testWrapDoS(_wrapAmount, waDAI.previewDeposit(_wrapAmount), SwapKind.EXACT_IN);
    }

    function testMintDoS() public {
        // Mint is an EXACT_OUT operation, since it's a wrap where we specify the wrapped amount out.
        _testWrapDoS(waDAI.previewDeposit(_wrapAmount), _wrapAmount, SwapKind.EXACT_OUT);
    }

    function testWithdrawDoS() public {
        // Withdraw is an EXACT_OUT operation, since it's an unwrap where we specify the underlying amount out.
        _testUnwrapDoS(_wrapAmount, waDAI.previewWithdraw(_wrapAmount), SwapKind.EXACT_OUT);
    }

    function testRedeemDoS() public {
        // Redeem is an EXACT_IN operation, since it's an unwrap where we specify the wrapped amount in.
        _testUnwrapDoS(waDAI.previewWithdraw(_wrapAmount), _wrapAmount, SwapKind.EXACT_IN);
    }

    function _testWrapDoS(uint256 amountGivenRaw, uint256 limitRaw, SwapKind kind) private {
        // Frontrunner will add more underlying tokens to the vault than the amount consumed by "mint", which could
        // make the vault "think" that an unwrap operation took place, instead of a wrap.
        uint256 frontrunnerUnderlyingAmount = _wrapAmount + 10;

        // Initializes the buffer with an amount that's not enough to fulfill the mint operation.
        vm.startPrank(lp);
        router.initializeBuffer(IERC4626(address(waDAI)), _wrapAmount / 10, waDAI.convertToShares(_wrapAmount / 10));
        vm.stopPrank();

        (, , IERC20[] memory tokens) = _getTokenArrayAndIndexesOfWaDaiBuffer();
        BaseVaultTest.Balances memory balancesBefore = getBalances(lp, tokens);

        (uint256 amountIn, uint256 amountOut) = abi.decode(
            vault.unlock(
                abi.encodeWithSelector(
                    BufferDoSProtectionTest.erc4626DoSHook.selector,
                    BufferWrapOrUnwrapParams({
                        kind: kind,
                        direction: WrappingDirection.WRAP,
                        wrappedToken: IERC4626(address(waDAI)),
                        amountGivenRaw: amountGivenRaw,
                        limitRaw: limitRaw,
                        userData: bytes("")
                    }),
                    lp,
                    frontrunnerUnderlyingAmount
                )
            ),
            (uint256, uint256)
        );

        _checkWrapResults(balancesBefore, amountIn, amountOut, frontrunnerUnderlyingAmount);
    }

    function _testUnwrapDoS(uint256 amountGivenRaw, uint256 limitRaw, SwapKind kind) private {
        // Frontrunner will add more wrapped tokens to the vault than the amount burned by "redeem", which could
        // trigger an arithmetic error in the vault.
        uint256 frontrunnerWrappedAmount = waDAI.previewWithdraw(2 * _wrapAmount);

        // Give alice enough liquidity to frontrun redeem call.
        dai.mint(alice, 2 * _wrapAmount);
        vm.startPrank(alice);
        dai.approve(address(waDAI), 2 * _wrapAmount);
        waDAI.deposit(2 * _wrapAmount, alice);
        vm.stopPrank();

        // Initializes the buffer with an amount that's not enough to fulfill the redeem operation.
        vm.startPrank(lp);
        router.initializeBuffer(IERC4626(address(waDAI)), _wrapAmount / 10, waDAI.convertToShares(_wrapAmount / 10));
        vm.stopPrank();

        (, , IERC20[] memory tokens) = _getTokenArrayAndIndexesOfWaDaiBuffer();
        BaseVaultTest.Balances memory balancesBefore = getBalances(lp, tokens);

        (uint256 amountIn, uint256 amountOut) = abi.decode(
            vault.unlock(
                abi.encodeWithSelector(
                    BufferDoSProtectionTest.erc4626DoSHook.selector,
                    BufferWrapOrUnwrapParams({
                        kind: kind,
                        direction: WrappingDirection.UNWRAP,
                        wrappedToken: IERC4626(address(waDAI)),
                        amountGivenRaw: amountGivenRaw,
                        limitRaw: limitRaw,
                        userData: bytes("")
                    }),
                    lp,
                    frontrunnerWrappedAmount
                )
            ),
            (uint256, uint256)
        );

        _checkUnwrapResults(balancesBefore, amountIn, amountOut, frontrunnerWrappedAmount);
    }

    function _checkWrapResults(
        BaseVaultTest.Balances memory balancesBefore,
        uint256 amountIn,
        uint256 amountOut,
        uint256 frontrunnerUnderlyingAmount
    ) private view {
        (uint256 daiIdx, uint256 waDaiIdx, IERC20[] memory tokens) = _getTokenArrayAndIndexesOfWaDaiBuffer();
        BaseVaultTest.Balances memory balancesAfter = getBalances(lp, tokens);

        // Check wrap results.
        assertGe(amountIn, _wrapAmount, "AmountIn (underlying deposited) is wrong");
        assertLe(amountOut, waDAI.previewDeposit(_wrapAmount), "AmountOut (wrapped minted) is wrong");

        // Check user balances.
        assertEq(
            balancesAfter.lpTokens[daiIdx],
            balancesBefore.lpTokens[daiIdx] - _wrapAmount,
            "LP balance of underlying token is wrong"
        );
        assertEq(
            balancesAfter.lpTokens[waDaiIdx],
            balancesBefore.lpTokens[waDaiIdx] + waDAI.previewDeposit(_wrapAmount),
            "LP balance of wrapped token is wrong"
        );

        // Check alice (frontrunner) balances. The frontrunner should lose the funds.
        assertEq(
            balancesAfter.aliceTokens[daiIdx],
            balancesBefore.aliceTokens[daiIdx] - frontrunnerUnderlyingAmount,
            "Frontrunner balance of underlying token is wrong"
        );
        assertEq(
            balancesAfter.aliceTokens[waDaiIdx],
            balancesBefore.aliceTokens[waDaiIdx],
            "Frontrunner balance of wrapped token is wrong"
        );

        // Check Vault reserves. Vault should have the reserves from before and the frontrunner amount (the user paid
        // for the amount deposited into the wrapper protocol, so the vault reserves should not be affected by that).
        assertEq(
            balancesAfter.vaultReserves[daiIdx],
            balancesBefore.vaultReserves[daiIdx] + frontrunnerUnderlyingAmount,
            "Vault reserves of underlying token is wrong"
        );
        assertEq(
            balancesAfter.vaultReserves[waDaiIdx],
            balancesBefore.vaultReserves[waDaiIdx],
            "Vault reserves of wrapped token is wrong"
        );

        // Check that Vault balances match vault reserves.
        assertEq(
            balancesAfter.vaultReserves[daiIdx],
            balancesAfter.vaultTokens[daiIdx],
            "Vault balance of underlying token is wrong"
        );
        assertEq(
            balancesAfter.vaultReserves[waDaiIdx],
            balancesAfter.vaultTokens[waDaiIdx],
            "Vault balance of wrapped token is wrong"
        );
    }

    function _checkUnwrapResults(
        BaseVaultTest.Balances memory balancesBefore,
        uint256 amountIn,
        uint256 amountOut,
        uint256 frontrunnerWrappedAmount
    ) private view {
        (uint256 daiIdx, uint256 waDaiIdx, IERC20[] memory tokens) = _getTokenArrayAndIndexesOfWaDaiBuffer();
        BaseVaultTest.Balances memory balancesAfter = getBalances(lp, tokens);

        // Check unwrap results.
        assertLe(amountOut, _wrapAmount, "AmountOut (underlying withdrawn) is wrong");
        assertGe(amountIn, waDAI.previewDeposit(_wrapAmount), "AmountIn (wrapped burned) is wrong");

        // Check user balances.
        assertEq(
            balancesAfter.lpTokens[daiIdx],
            balancesBefore.lpTokens[daiIdx] + _wrapAmount,
            "LP balance of underlying token is wrong"
        );
        assertEq(
            balancesAfter.lpTokens[waDaiIdx],
            balancesBefore.lpTokens[waDaiIdx] - waDAI.previewWithdraw(_wrapAmount),
            "LP balance of wrapped token is wrong"
        );

        // Check alice (frontrunner) balances. The frontrunner should lose the funds.
        assertEq(
            balancesAfter.aliceTokens[daiIdx],
            balancesBefore.aliceTokens[daiIdx],
            "Frontrunner balance of underlying token is wrong"
        );
        assertEq(
            balancesAfter.aliceTokens[waDaiIdx],
            balancesBefore.aliceTokens[waDaiIdx] - frontrunnerWrappedAmount,
            "Frontrunner balance of wrapped token is wrong"
        );

        // Check Vault reserves. Vault should have the reserves from before and the frontrunner amount (the user paid
        // for the amount deposited into the wrapper protocol, so the vault reserves should not be affected by that).
        assertEq(
            balancesAfter.vaultReserves[daiIdx],
            balancesBefore.vaultReserves[daiIdx],
            "Vault reserves of underlying token is wrong"
        );
        assertEq(
            balancesAfter.vaultReserves[waDaiIdx],
            balancesBefore.vaultReserves[waDaiIdx] + frontrunnerWrappedAmount,
            "Vault reserves of wrapped token is wrong"
        );

        // Check that Vault balances match vault reserves.
        assertEq(
            balancesAfter.vaultReserves[daiIdx],
            balancesAfter.vaultTokens[daiIdx],
            "Vault balance of underlying token is wrong"
        );
        assertEq(
            balancesAfter.vaultReserves[waDaiIdx],
            balancesAfter.vaultTokens[waDaiIdx],
            "Vault balance of wrapped token is wrong"
        );
    }

    function _getTokenArrayAndIndexesOfWaDaiBuffer()
        private
        view
        returns (uint256 daiIdx, uint256 waDaiIdx, IERC20[] memory tokens)
    {
        (daiIdx, waDaiIdx) = getSortedIndexes(address(dai), address(waDAI));
        tokens = new IERC20[](2);
        tokens[daiIdx] = dai;
        tokens[waDaiIdx] = IERC20(address(waDAI));
    }

    /**
     * @notice Hook used to interact with the ERC4626 wrap/unwrap primitive of the Vault.
     * @dev The standard router cannot be used to test DoS attacks because it charges the underlying token upfront to
     * cover wrap operations, which sync the reserves of the Vault and prevents the attack. To effectively test for
     * DoS vulnerabilities, we need a custom malicious router that performs the donation after the initial payment
     * and settlement. This will leave the Vault's reserves out of sync with its balances.
     */
    function erc4626DoSHook(
        BufferWrapOrUnwrapParams memory params,
        address sender,
        uint256 frontrunnerAmount
    ) external returns (uint256 amountIn, uint256 amountOut) {
        IERC20 underlyingToken = IERC20(params.wrappedToken.asset());
        IERC20 wrappedToken = IERC20(address(params.wrappedToken));

        // Transfer tokens to the vault and settle, since the Vault needs to have enough tokens in the reserves to
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

            // Donate more underlying to the vault than the amount that will be deposited, so the vault can think that
            // it's an unwrap because the reserves of underlying tokens increased after the wrap operation. Don't
            // settle, or else the vault will measure the difference of underlying reserves correctly.
            vm.prank(alice);
            dai.transfer(address(vault), frontrunnerAmount);
        } else {
            if (params.kind == SwapKind.EXACT_IN) {
                wrappedToken.transferFrom(sender, address(vault), params.amountGivenRaw);
                vault.settle(wrappedToken, params.amountGivenRaw);
            } else {
                wrappedToken.transferFrom(sender, address(vault), params.limitRaw);
                vault.settle(wrappedToken, params.limitRaw);
            }

            // Donate more wrapped to the vault than the amount that will be burned, so an arithmetic error can be
            // triggered in the vault since the wrapped balance after an unwrap operation should decrease, but with the
            // donation it increases. Don't settle, or else the vault will measure the difference of wrapped reserves
            // correctly.
            vm.prank(alice);
            waDAI.transfer(address(vault), frontrunnerAmount);
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
