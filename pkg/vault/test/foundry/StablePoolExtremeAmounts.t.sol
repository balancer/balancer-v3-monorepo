// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { StablePoolFactory } from "@balancer-labs/v3-pool-stable/contracts/StablePoolFactory.sol";
import { StablePool } from "@balancer-labs/v3-pool-stable/contracts/StablePool.sol";

import { BaseExtremeAmountsTest } from "./utils/BaseExtremeAmountsTest.sol";

contract StablePoolExtremeAmountsTest is BaseExtremeAmountsTest {
    using CastingHelpers for *;

    uint256 internal constant DEFAULT_AMP_FACTOR = 200;

    function setUp() public virtual override {
        BaseExtremeAmountsTest.setUp();
    }

    function _createPool(address[] memory tokens, string memory label) internal override returns (address) {
        StablePoolFactory factory = new StablePoolFactory(IVault(address(vault)), 365 days, "Factory v1", "Pool v1");

        PoolRoleAccounts memory roleAccounts;

        StablePool newPool = StablePool(
            factory.create(
                "Stable Pool",
                "STABLE",
                vault.buildTokenConfig(tokens.asIERC20()),
                DEFAULT_AMP_FACTOR,
                roleAccounts,
                BASE_MIN_SWAP_FEE, // Set min swap fee
                address(0),
                false, // Do not enable donations
                false, // Do not disable unbalanced add/remove liquidity
                ZERO_BYTES32
            )
        );
        vm.label(address(newPool), label);

        return address(newPool);
    }

    function _boundBalances(uint256[2] memory balancesRaw) internal pure override returns (uint256[] memory balances) {
        balances = new uint256[](2);
        balances[0] = bound(balancesRaw[0], MIN_BALANCE, MAX_BALANCE);
        balances[1] = balances[0];
    }
}
