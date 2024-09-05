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

contract E2eErc4626SwapsStableTest is E2eErc4626SwapsTest {
    uint256 internal constant DEFAULT_SWAP_FEE = 1e16; // 1%
    uint256 internal constant DEFAULT_AMP_FACTOR = 200;

    function setUp() public override {
        super.setUp();

        // Makes sure Bob has enough tokens to pay for DAI and USDC wraps.
        dai.mint(bob, 1000 * erc4626PoolInitialAmount);
        usdc.mint(bob, 1000 * erc4626PoolInitialAmount);
    }

    function createPool() internal override returns (address) {
        string memory poolName = "ERC4626 Stable Pool";

        // Gets the tokenConfig from BaseERC4626BufferTest (it means, waDAI and waUSDC with rate providers).
        TokenConfig[] memory tokenConfig = getTokenConfig();

        StablePoolFactory factory = new StablePoolFactory(IVault(address(vault)), 365 days, "Factory v1", "Pool v1");
        PoolRoleAccounts memory roleAccounts;

        // Allow pools created by `factory` to use poolHooksMock hooks.
        PoolHooksMock(poolHooksContract).allowFactory(address(factory));

        StablePool newPool = StablePool(
            factory.create(
                poolName,
                poolName,
                tokenConfig,
                DEFAULT_AMP_FACTOR,
                roleAccounts,
                DEFAULT_SWAP_FEE,
                poolHooksContract,
                false, // Do not enable donations
                false, // Do not disable unbalanced add/remove liquidity
                ZERO_BYTES32
            )
        );
        vm.label(address(newPool), poolName);

        // Cannot set the pool creator directly on a standard Balancer stable pool factory.
        vault.manualSetPoolCreator(address(newPool), lp);

        ProtocolFeeControllerMock feeController = ProtocolFeeControllerMock(address(vault.getProtocolFeeController()));
        feeController.manualSetPoolCreator(address(newPool), lp);

        erc4626Pool = address(newPool);
        return erc4626Pool;
    }
}
