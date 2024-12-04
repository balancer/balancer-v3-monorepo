// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { PoolHooksMock } from "@balancer-labs/v3-vault/contracts/test/PoolHooksMock.sol";
import { ProtocolFeeControllerMock } from "@balancer-labs/v3-vault/contracts/test/ProtocolFeeControllerMock.sol";
import { E2eErc4626SwapsTest } from "@balancer-labs/v3-vault/test/foundry/E2eErc4626Swaps.t.sol";

import { StablePoolFactory } from "../../contracts/StablePoolFactory.sol";
import { StablePool } from "../../contracts/StablePool.sol";
import { StablePoolContractsDeployer } from "./utils/StablePoolContractsDeployer.sol";

contract E2eErc4626SwapsStableTest is E2eErc4626SwapsTest, StablePoolContractsDeployer {
    uint256 internal constant DEFAULT_SWAP_FEE = 1e16; // 1%
    uint256 internal constant DEFAULT_AMP_FACTOR = 200;

    function createPool() internal override returns (address newPool, bytes memory poolArgs) {
        string memory name = "ERC4626 Stable Pool";
        string memory symbol = "STABLE";
        string memory poolVersion = "Pool v1";

        // Gets the tokenConfig from BaseERC4626BufferTest (it means, waDAI and waUSDC with rate providers).
        TokenConfig[] memory tokenConfig = getTokenConfig();

        StablePoolFactory factory = deployStablePoolFactory(
            IVault(address(vault)),
            365 days,
            "Factory v1",
            poolVersion
        );
        PoolRoleAccounts memory roleAccounts;

        // Allow pools created by `factory` to use poolHooksMock hooks.
        PoolHooksMock(poolHooksContract).allowFactory(address(factory));

        newPool = factory.create(
            name,
            symbol,
            tokenConfig,
            DEFAULT_AMP_FACTOR,
            roleAccounts,
            DEFAULT_SWAP_FEE,
            poolHooksContract,
            false, // Do not enable donations
            false, // Do not disable unbalanced add/remove liquidity
            ZERO_BYTES32
        );
        vm.label(address(newPool), name);

        // Cannot set the pool creator directly on a standard Balancer stable pool factory.
        vault.manualSetPoolCreator(address(newPool), lp);

        ProtocolFeeControllerMock feeController = ProtocolFeeControllerMock(address(vault.getProtocolFeeController()));
        feeController.manualSetPoolCreator(address(newPool), lp);

        poolArgs = abi.encode(
            StablePool.NewPoolParams({
                name: name,
                symbol: symbol,
                amplificationParameter: DEFAULT_AMP_FACTOR,
                version: poolVersion
            }),
            vault
        );
    }
}
