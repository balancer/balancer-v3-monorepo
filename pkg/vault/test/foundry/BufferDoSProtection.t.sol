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

    ERC4626TestToken internal waDAI;

    uint256 private constant _userAmount = 10e6 * 1e18;
    uint256 private constant _wrapAmount = _userAmount / 100;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        waDAI = new ERC4626TestToken(dai, "Wrapped aDAI", "waDAI", 18);
        vm.label(address(waDAI), "waDAI");

        initializeLp();
    }

    function initializeLp() private {
        // Create and fund buffer pools
        vm.startPrank(lp);

        dai.mint(lp, _userAmount);
        dai.approve(address(waDAI), _userAmount);
        waDAI.deposit(_userAmount, lp);

        waDAI.approve(address(permit2), MAX_UINT256);
        permit2.approve(address(waDAI), address(router), type(uint160).max, type(uint48).max);
        permit2.approve(address(waDAI), address(batchRouter), type(uint160).max, type(uint48).max);
        vm.stopPrank();
    }

    function testDepositDoS() public {
        // Frontrunner will add more tokens to the vault than the amount consumed by "deposit", which could make the
        // vault "think" that an unwrap operation took place, instead of a wrap.
        uint256 frontrunnerAmount = _wrapAmount + 10;

        // Initializes the buffer with an amount that's not possible to fulfill the deposit operation.
        vm.prank(lp);
        router.initializeBuffer(IERC4626(address(waDAI)), _wrapAmount / 10, _wrapAmount / 10);

        (uint256 daiIdx, uint256 waDaiIdx, IERC20[] memory tokens) = _getTokenArrayAndIndexesOfWaDaiBuffer();

        BaseVaultTest.Balances memory balancesBefore = getBalances(lp, tokens);

        // Approves this test to act as a router and move DAI from lp to vault.
        vm.prank(lp);
        dai.approve(address(this), _wrapAmount);

        (uint256 amountIn, uint256 amountOut) = abi.decode(
            vault.unlock(
                abi.encodeWithSelector(
                    BufferDoSProtectionTest.erc4626DoSHook.selector,
                    BufferWrapOrUnwrapParams({
                        kind: SwapKind.EXACT_IN,
                        direction: WrappingDirection.WRAP,
                        wrappedToken: IERC4626(address(waDAI)),
                        amountGivenRaw: _wrapAmount,
                        limitRaw: 0,
                        userData: bytes("")
                    }),
                    lp,
                    frontrunnerAmount
                )
            ),
            (uint256, uint256)
        );

        BaseVaultTest.Balances memory balancesAfter = getBalances(lp, tokens);

        // Check wrap/unwrap results.
        assertEq(amountIn, _wrapAmount, "AmountIn (underlying deposited) is wrong");
        assertEq(amountOut, waDAI.previewDeposit(_wrapAmount), "AmountOut (wrapped minted) is wrong");

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
            balancesBefore.aliceTokens[daiIdx] - frontrunnerAmount,
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
            balancesBefore.vaultReserves[daiIdx] + frontrunnerAmount,
            "Vault reserves of underlying token is wrong"
        );
        assertEq(
            balancesAfter.vaultReserves[waDaiIdx],
            balancesBefore.vaultReserves[waDaiIdx],
            "Vault reserves of wrapped token is wrong"
        );

        // Check Vault balances. Vault balances should match vault reserves.
        assertEq(
            balancesAfter.vaultReserves[daiIdx],
            balancesAfter.vaultTokens[daiIdx],
            "Vault balance of underlying token is wrong"
        );
        assertEq(
            balancesAfter.vaultReserves[waDaiIdx],
            balancesBefore.vaultTokens[waDaiIdx],
            "Vault balance of wrapped token is wrong"
        );
    }

    /// @notice Hook used to interact with ERC4626 wrap/unwrap primitive of the vault.
    function erc4626DoSHook(
        BufferWrapOrUnwrapParams memory params,
        address sender,
        uint256 frontrunnerAmount
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
            dai.transfer(address(vault), frontrunnerAmount);
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
}
