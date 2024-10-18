// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { Rounding } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";

import { Gyro2CLPPool } from "../../contracts/Gyro2CLPPool.sol";

contract ComputeBalance2CLPTest is BaseVaultTest {
    using FixedPoint for uint256;

    Gyro2CLPPool private _gyroPool;
    uint256 private _sqrtAlpha = 997496867163000167; // alpha (lower price rate) = 0.995
    uint256 private _sqrtBeta = 1002496882788171068; // beta (upper price rate) = 1.005

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        _gyroPool = new Gyro2CLPPool(
            Gyro2CLPPool.GyroParams({ name: "GyroPool", symbol: "GRP", sqrtAlpha: _sqrtAlpha, sqrtBeta: _sqrtBeta }),
            vault
        );
        vm.label(address(_gyroPool), "GyroPool");
    }

    function testComputeNewXBalance__Fuzz(uint256 balanceX, uint256 balanceY, uint256 deltaX) public view {
        balanceX = bound(balanceX, 1e16, 1e27);
        // Price range is [alpha,beta], so balanceY needs to be between alpha*balanceX and beta*balanceX
        balanceY = bound(
            balanceY,
            balanceX.mulDown(_sqrtAlpha).mulDown(_sqrtAlpha),
            balanceX.mulDown(_sqrtBeta).mulDown(_sqrtBeta)
        );
        uint256[] memory balances = new uint256[](2);
        balances[0] = balanceX;
        balances[1] = balanceY;
        uint256 oldInvariant = _gyroPool.computeInvariant(balances, Rounding.ROUND_DOWN);

        deltaX = bound(deltaX, 1e16, 1e30);
        balances[0] = balances[0] + deltaX;
        uint256 newInvariant = _gyroPool.computeInvariant(balances, Rounding.ROUND_DOWN);

        // Restores the balances to original balances, to calculate computeBalance properly.
        balances[0] = balanceX;

        uint256 invariantRatio = newInvariant.divDown(oldInvariant);
        uint256 newXBalance = _gyroPool.computeBalance(balances, 0, invariantRatio);

        // 0.000000000002% error
        assertApproxEqRel(newXBalance, balanceX + deltaX, 2e4, "Balance of X does not match");
    }

    function testComputeNewYBalance__Fuzz(uint256 balanceX, uint256 balanceY, uint256 deltaY) public view {
        balanceX = bound(balanceX, 1e16, 1e27);
        // Price range is [alpha,beta], so balanceY needs to be between alpha*balanceX and beta*balanceX
        balanceY = bound(
            balanceY,
            balanceX.mulDown(_sqrtAlpha).mulDown(_sqrtAlpha),
            balanceX.mulDown(_sqrtBeta).mulDown(_sqrtBeta)
        );
        uint256[] memory balances = new uint256[](2);
        balances[0] = balanceX;
        balances[1] = balanceY;
        uint256 oldInvariant = _gyroPool.computeInvariant(balances, Rounding.ROUND_DOWN);

        deltaY = bound(deltaY, 1e16, 1e30);
        balances[1] = balances[1] + deltaY;
        uint256 newInvariant = _gyroPool.computeInvariant(balances, Rounding.ROUND_DOWN);

        // Restores the balances to original balances, to calculate computeBalance properly.
        balances[1] = balanceY;

        uint256 invariantRatio = newInvariant.divDown(oldInvariant);
        uint256 newYBalance = _gyroPool.computeBalance(balances, 1, invariantRatio);

        // 0.000000000002% error
        assertApproxEqRel(newYBalance, balanceY + deltaY, 2e4, "Balance of Y does not match");
    }
}
