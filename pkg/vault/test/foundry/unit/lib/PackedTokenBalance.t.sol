// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { PackedTokenBalance } from "../../../../contracts/lib/PackedTokenBalance.sol";

contract PackedTokenBalanceTest is Test {
    function testToFromPackedBalance__Fuzz(uint128 raw, uint128 live) public {
        bytes32 balance = PackedTokenBalance.toPackedBalance(raw, live);

        (uint256 recoveredRaw, uint256 recoveredLive) = PackedTokenBalance.fromPackedBalance(balance);

        assertEq(recoveredRaw, raw);
        assertEq(recoveredLive, live);
    }

    function testPackedTokenBalanceGetters__Fuzz(uint128 raw, uint128 live) public {
        bytes32 balance = PackedTokenBalance.toPackedBalance(raw, live);

        uint256 recoveredRaw = PackedTokenBalance.getRawBalance(balance);
        uint256 recoveredLive = PackedTokenBalance.getLastLiveBalanceScaled18(balance);

        assertEq(recoveredRaw, raw);
        assertEq(recoveredLive, live);
    }

    function testPackedTokenBalanceSetters__Fuzz(bytes32 balance, uint128 newBalanceValue) public {
        (uint256 recoveredRaw, uint256 recoveredLive) = PackedTokenBalance.fromPackedBalance(balance);

        // Set new raw balance (should not change live).
        bytes32 newBalance = PackedTokenBalance.setRawBalance(balance, newBalanceValue);

        uint256 newRecoveredRaw = PackedTokenBalance.getRawBalance(newBalance);
        uint256 newRecoveredLive = PackedTokenBalance.getLastLiveBalanceScaled18(newBalance);

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
        PackedTokenBalance.setRawBalance(balance, overMaxBalanceValue);
    }
}
