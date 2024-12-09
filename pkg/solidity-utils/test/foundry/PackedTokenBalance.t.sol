// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { PackedTokenBalance } from "../../contracts/helpers/PackedTokenBalance.sol";

contract PackedTokenBalanceTest is Test {
    using PackedTokenBalance for bytes32;

    function testToFromPackedBalance__Fuzz(uint128 raw, uint128 live) public pure {
        bytes32 balance = PackedTokenBalance.toPackedBalance(raw, live);

        (uint256 recoveredRaw, uint256 recoveredLive) = balance.fromPackedBalance();

        assertEq(recoveredRaw, raw);
        assertEq(recoveredLive, live);
    }

    function testPackedTokenBalanceGetters__Fuzz(uint128 raw, uint128 live) public pure {
        bytes32 balance = PackedTokenBalance.toPackedBalance(raw, live);

        uint256 recoveredRaw = balance.getBalanceRaw();
        uint256 recoveredLive = balance.getBalanceDerived();

        assertEq(recoveredRaw, raw);
        assertEq(recoveredLive, live);
    }

    function testPackedTokenBalanceSetters__Fuzz(bytes32 balance, uint128 newBalanceValue) public pure {
        (, uint256 recoveredLive) = PackedTokenBalance.fromPackedBalance(balance);

        // Set new raw balance (should not change live).
        bytes32 newBalance = balance.setBalanceRaw(newBalanceValue);

        uint256 newRecoveredRaw = newBalance.getBalanceRaw();
        uint256 newRecoveredLive = newBalance.getBalanceDerived();

        assertEq(newRecoveredRaw, newBalanceValue);
        assertEq(newRecoveredLive, recoveredLive);
    }

    function testOverflow__Fuzz(bytes32 balance, uint128 validBalanceValue, uint256 overMaxBalanceValue) public {
        overMaxBalanceValue = bound(overMaxBalanceValue, uint256(2 ** (128)), type(uint256).max);

        vm.expectRevert(PackedTokenBalance.BalanceOverflow.selector);
        PackedTokenBalance.toPackedBalance(validBalanceValue, overMaxBalanceValue);

        vm.expectRevert(PackedTokenBalance.BalanceOverflow.selector);
        PackedTokenBalance.toPackedBalance(overMaxBalanceValue, validBalanceValue);

        vm.expectRevert(PackedTokenBalance.BalanceOverflow.selector);
        balance.setBalanceRaw(overMaxBalanceValue);
    }
}
