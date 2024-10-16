// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";

import { LiquidityApproximationTest } from "@balancer-labs/v3-vault/test/foundry/LiquidityApproximation.t.sol";

import { GyroECLPPoolFactory } from "../../contracts/GyroECLPPoolFactory.sol";
import { GyroECLPPool } from "../../contracts/GyroECLPPool.sol";
import { GyroECLPMath } from "../../contracts/lib/GyroECLPMath.sol";

contract LiquidityApproximationECLPTest is LiquidityApproximationTest {
    using CastingHelpers for address[];

    uint256 poolCreationNonce;

    // Extracted from pool 0x2191df821c198600499aa1f0031b1a7514d7a7d9 on Mainnet.
    int256 internal _paramsAlpha = 998502246630054917;
    int256 internal _paramsBeta = 1000200040008001600;
    int256 internal _paramsC = 707106781186547524;
    int256 internal _paramsS = 707106781186547524;
    int256 internal _paramsLambda = 4000000000000000000000;

    int256 internal _tauAlphaX = -94861212813096057289512505574275160547;
    int256 internal _tauAlphaY = 31644119574235279926451292677567331630;
    int256 internal _tauBetaX = 37142269533113549537591131345643981951;
    int256 internal _tauBetaY = 92846388265400743995957747409218517601;
    int256 internal _u = 66001741173104803338721745994955553010;
    int256 internal _v = 62245253919818011890633399060291020887;
    int256 internal _w = 30601134345582732000058913853921008022;
    int256 internal _z = -28859471639991253843240999485797747790;
    int256 internal _dSq = 99999999999999999886624093342106115200;

    function setUp() public virtual override {
        LiquidityApproximationTest.setUp();

        // The invariant of ECLP pools are smaller.
        maxAmount = 1e6 * 1e18;
    }

    function _createPool(address[] memory tokens, string memory label) internal override returns (address) {
        GyroECLPPoolFactory factory = new GyroECLPPoolFactory(IVault(address(vault)), 365 days);

        PoolRoleAccounts memory roleAccounts;

        GyroECLPMath.Params memory params = GyroECLPMath.Params({
            alpha: _paramsAlpha,
            beta: _paramsBeta,
            c: _paramsC,
            s: _paramsS,
            lambda: _paramsLambda
        });

        GyroECLPMath.DerivedParams memory derivedParams = GyroECLPMath.DerivedParams({
            tauAlpha: GyroECLPMath.Vector2(_tauAlphaX, _tauAlphaY),
            tauBeta: GyroECLPMath.Vector2(_tauBetaX, _tauBetaY),
            u: _u,
            v: _v,
            w: _w,
            z: _z,
            dSq: _dSq
        });

        GyroECLPPool newPool = GyroECLPPool(
            factory.create(
                "Gyro ECLP Pool",
                "GRP",
                vault.buildTokenConfig(tokens.asIERC20()),
                params,
                derivedParams,
                roleAccounts,
                0,
                address(0),
                ZERO_BYTES32
            )
        );
        vm.label(address(newPool), label);
        return address(newPool);
    }
}
