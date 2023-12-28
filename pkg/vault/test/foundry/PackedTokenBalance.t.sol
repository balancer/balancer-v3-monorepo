// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { PackedTokenBalance } from "../../contracts/lib/PackedTokenBalance.sol";

contract PackedTokenBalanceTest is Test {
    function testToFromPackedBalance(uint128 raw, uint128 live) public {
        bytes32 balance = PackedTokenBalance.toPackedBalance(raw, live);

        (uint256 recoveredRaw, uint256 recoveredLive) = PackedTokenBalance.fromPackedBalance(balance);

        assertEq(recoveredRaw, raw);
        assertEq(recoveredLive, live);
    }

    function testPackedTokenBalanceGetters(uint128 raw, uint128 live) public {
        bytes32 balance = PackedTokenBalance.toPackedBalance(raw, live);

        uint256 recoveredRaw = PackedTokenBalance.getRawBalance(balance);
        uint256 recoveredLive = PackedTokenBalance.getLastLiveBalanceScaled18(balance);

        assertEq(recoveredRaw, raw);
        assertEq(recoveredLive, live);
    }

    function testPackedTokenBalanceSetters(bytes32 balance, uint128 newBalanceValue) public {
        (uint256 recoveredRaw, uint256 recoveredLive) = PackedTokenBalance.fromPackedBalance(balance);

        // Set new raw balance (should not change live).
        bytes32 newBalance = PackedTokenBalance.setRawBalance(balance, newBalanceValue);

        uint256 newRecoveredRaw = PackedTokenBalance.getRawBalance(newBalance);
        uint256 newRecoveredLive = PackedTokenBalance.getLastLiveBalanceScaled18(newBalance);

        assertEq(newRecoveredRaw, newBalanceValue);
        assertEq(newRecoveredLive, recoveredLive);

        // Set new live balance (should not change raw).
        newBalance = PackedTokenBalance.setLastLiveBalanceScaled18(balance, newBalanceValue);
        
        newRecoveredRaw = PackedTokenBalance.getRawBalance(newBalance);
        newRecoveredLive = PackedTokenBalance.getLastLiveBalanceScaled18(newBalance);

        assertEq(newRecoveredRaw, recoveredRaw);
        assertEq(newRecoveredLive, newBalanceValue);
    }
}