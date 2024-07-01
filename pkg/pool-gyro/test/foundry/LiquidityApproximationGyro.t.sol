// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";

import { Gyro2CLPPoolFactory } from "../../contracts/Gyro2CLPPoolFactory.sol";
import { Gyro2CLPPool } from "../../contracts/Gyro2CLPPool.sol";

import { LiquidityApproximationTest } from "@balancer-labs/v3-vault/test/foundry/LiquidityApproximation.t.sol";
import { Gyro2CLPPool } from "../../contracts/Gyro2CLPPool.sol";

contract LiquidityApproximationGyroTest is LiquidityApproximationTest {
    using ArrayHelpers for *;

    uint256 poolCreationNonce;

    uint256 private _sqrtAlpha = 997496867163000167; // alpha (lower price rate) = 0.995
    uint256 private _sqrtBeta = 1002496882788171068; // beta (upper price rate) = 1.005

    function setUp() public virtual override {
        LiquidityApproximationTest.setUp();
    }

    function _createPool(address[] memory tokens, string memory label) internal override returns (address) {
        Gyro2CLPPoolFactory factory = new Gyro2CLPPoolFactory(IVault(address(vault)), 365 days);

        PoolRoleAccounts memory roleAccounts;

        Gyro2CLPPool newPool = Gyro2CLPPool(
            factory.create(
                "Gyro 2CLP Pool",
                "GRP",
                vault.buildTokenConfig(tokens.asIERC20()),
                _sqrtAlpha,
                _sqrtBeta,
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
