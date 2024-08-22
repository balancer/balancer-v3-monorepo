// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";

import { PoolHooksMock } from "@balancer-labs/v3-vault/contracts/test/PoolHooksMock.sol";
import { ProtocolFeeControllerMock } from "@balancer-labs/v3-vault/contracts/test/ProtocolFeeControllerMock.sol";
import { RateProviderMock } from "@balancer-labs/v3-vault/contracts/test/RateProviderMock.sol";
import { E2eSwapRateProvider } from "@balancer-labs/v3-vault/test/foundry/E2eSwapRateProvider.t.sol";

import { StablePoolFactory } from "../../contracts/StablePoolFactory.sol";
import { StablePool } from "../../contracts/StablePool.sol";

contract E2eSwapRateProviderStableTest is E2eSwapRateProvider {
    using CastingHelpers for address[];

    uint256 internal constant DEFAULT_SWAP_FEE = 1e16; // 1%
    uint256 internal constant DEFAULT_AMP_FACTOR = 200;

    function _createPool(address[] memory tokens, string memory label) internal override returns (address) {
        rateProviderTokenA = new RateProviderMock();
        rateProviderTokenB = new RateProviderMock();
        // Mock rates, so all tests that keep the rate constant use a rate different than 1.
        rateProviderTokenA.mockRate(5.2453235e18);
        rateProviderTokenB.mockRate(0.4362784e18);

        IRateProvider[] memory rateProviders = new IRateProvider[](2);
        rateProviders[tokenAIdx] = IRateProvider(address(rateProviderTokenA));
        rateProviders[tokenBIdx] = IRateProvider(address(rateProviderTokenB));

        StablePoolFactory factory = new StablePoolFactory(IVault(address(vault)), 365 days, "Factory v1", "Pool v1");
        PoolRoleAccounts memory roleAccounts;

        // Allow pools created by `factory` to use poolHooksMock hooks.
        PoolHooksMock(poolHooksContract).allowFactory(address(factory));

        StablePool newPool = StablePool(
            factory.create(
                "Stable Pool",
                "STABLE",
                vault.buildTokenConfig(tokens.asIERC20(), rateProviders),
                DEFAULT_AMP_FACTOR,
                roleAccounts,
                DEFAULT_SWAP_FEE, // 1% swap fee, but test will override it
                poolHooksContract,
                false, // Do not enable donations
                false, // Do not disable unbalanced add/remove liquidity
                ZERO_BYTES32
            )
        );
        vm.label(address(newPool), label);

        // Cannot set the pool creator directly on a standard Balancer stable pool factory.
        vault.manualSetPoolCreator(address(newPool), lp);

        ProtocolFeeControllerMock feeController = ProtocolFeeControllerMock(address(vault.getProtocolFeeController()));
        feeController.manualSetPoolCreator(address(newPool), lp);

        return address(newPool);
    }
}
