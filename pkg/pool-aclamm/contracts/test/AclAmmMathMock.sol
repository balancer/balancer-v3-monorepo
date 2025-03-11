// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { Rounding } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { SqrtQ0State, AclAmmMath } from "../lib/AclAmmMath.sol";

contract AclAmmMathMock {
    function computeInvariant(
        uint256[] memory balancesScaled18,
        uint256[] memory lastVirtualBalances,
        uint256 c,
        uint256 sqrtQ0,
        uint256 lastTimestamp,
        uint256 centerednessMargin,
        SqrtQ0State memory sqrtQ0State,
        Rounding rounding
    ) external view returns (uint256) {
        return
            AclAmmMath.computeInvariant(
                balancesScaled18,
                lastVirtualBalances,
                c,
                sqrtQ0,
                lastTimestamp,
                centerednessMargin,
                sqrtQ0State,
                rounding
            );
    }

    function calculateOutGivenIn(
        uint256[] memory balancesScaled18,
        uint256[] memory virtualBalances,
        uint256 tokenInIndex,
        uint256 tokenOutIndex,
        uint256 amountGivenScaled18
    ) external pure returns (uint256) {
        return
            AclAmmMath.calculateOutGivenIn(
                balancesScaled18,
                virtualBalances,
                tokenInIndex,
                tokenOutIndex,
                amountGivenScaled18
            );
    }

    function calculateInGivenOut(
        uint256[] memory balancesScaled18,
        uint256[] memory virtualBalances,
        uint256 tokenInIndex,
        uint256 tokenOutIndex,
        uint256 amountGivenScaled18
    ) external pure returns (uint256) {
        return
            AclAmmMath.calculateInGivenOut(
                balancesScaled18,
                virtualBalances,
                tokenInIndex,
                tokenOutIndex,
                amountGivenScaled18
            );
    }

    function initializeVirtualBalances(
        uint256[] memory balancesScaled18,
        uint256 sqrtQ0
    ) external pure returns (uint256[] memory virtualBalances) {
        return AclAmmMath.initializeVirtualBalances(balancesScaled18, sqrtQ0);
    }

    function getVirtualBalances(
        uint256[] memory balancesScaled18,
        uint256[] memory lastVirtualBalances,
        uint256 c,
        uint256 sqrtQ0,
        uint256 lastTimestamp,
        uint256 centerednessMargin,
        uint256 currentTime,
        SqrtQ0State memory sqrtQ0State
    ) external view returns (uint256[] memory virtualBalances, bool changed) {
        return
            AclAmmMath.getVirtualBalances(
                balancesScaled18,
                lastVirtualBalances,
                c,
                sqrtQ0,
                lastTimestamp,
                centerednessMargin,
                currentTime,
                sqrtQ0State
            );
    }

    function isPoolInRange(
        uint256[] memory balancesScaled18,
        uint256[] memory virtualBalances,
        uint256 centerednessMargin
    ) external pure returns (bool) {
        return AclAmmMath.isPoolInRange(balancesScaled18, virtualBalances, centerednessMargin);
    }

    function calculateCenteredness(
        uint256[] memory balancesScaled18,
        uint256[] memory virtualBalances
    ) external pure returns (uint256) {
        return AclAmmMath.calculateCenteredness(balancesScaled18, virtualBalances);
    }

    function calculateSqrtQ0(
        uint256 currentTime,
        uint256 startSqrtQ0,
        uint256 endSqrtQ0,
        uint256 startTime,
        uint256 endTime
    ) external pure returns (uint256) {
        return AclAmmMath.calculateSqrtQ0(currentTime, startSqrtQ0, endSqrtQ0, startTime, endTime);
    }

    function isAboveCenter(
        uint256[] memory balancesScaled18,
        uint256[] memory virtualBalances
    ) external pure returns (bool) {
        return AclAmmMath.isAboveCenter(balancesScaled18, virtualBalances);
    }

    function parseIncreaseDayRate(uint256 increaseDayRate) external pure returns (uint256) {
        return AclAmmMath.parseIncreaseDayRate(increaseDayRate);
    }
}
