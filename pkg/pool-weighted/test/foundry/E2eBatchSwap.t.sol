// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";

import { ProtocolFeeControllerMock } from "@balancer-labs/v3-vault/contracts/test/ProtocolFeeControllerMock.sol";
import { E2eBatchSwapTest } from "@balancer-labs/v3-vault/test/foundry/E2eBatchSwap.t.sol";

import { WeightedPoolFactory } from "../../contracts/WeightedPoolFactory.sol";
import { WeightedPool } from "../../contracts/WeightedPool.sol";

contract E2eBatchSwapWeightedTest is E2eBatchSwapTest {
    using ArrayHelpers for *;
    using CastingHelpers for address[];

    uint256 internal constant DEFAULT_SWAP_FEE_WEIGHTED = 1e12; // 0.0001%
    uint256 internal poolCreationNonce;

    function setUp() public override {
        E2eBatchSwapTest.setUp();

        vm.startPrank(poolCreator);
        // Weighted pools may be drained if there are no lp fees. So, set the creator fee to 99% to add some lp fee
        // back to the pool and ensure the invariant doesn't decrease.
        feeController.setPoolCreatorSwapFeePercentage(poolA, 99e16);
        feeController.setPoolCreatorSwapFeePercentage(poolB, 99e16);
        feeController.setPoolCreatorSwapFeePercentage(poolC, 99e16);
        vm.stopPrank();
    }

    function _setUpVariables() internal override {
        tokenA = dai;
        tokenB = usdc;
        tokenC = ERC20TestToken(address(weth));
        tokenD = wsteth;

        sender = lp;
        poolCreator = lp;

        minSwapAmountTokenA = poolInitAmount / 1e3;
        minSwapAmountTokenD = poolInitAmount / 1e3;

        // Divide init amount by 10 to make sure LP has enough tokens to pay for the swap in case of EXACT_OUT.
        maxSwapAmountTokenA = poolInitAmount / 10;
        maxSwapAmountTokenD = poolInitAmount / 10;
    }

    /// @notice Overrides BaseVaultTest _createPool(). This pool is used by E2eSwapTest tests.
    function _createPool(address[] memory tokens, string memory label) internal override returns (address) {
        WeightedPoolFactory factory = new WeightedPoolFactory(
            IVault(address(vault)),
            365 days,
            "Factory v1",
            "Pool v1"
        );
        PoolRoleAccounts memory roleAccounts;

        WeightedPool newPool = WeightedPool(
            factory.create(
                "50/50 Weighted Pool",
                "50_50WP",
                vault.buildTokenConfig(tokens.asIERC20()),
                [uint256(50e16), uint256(50e16)].toMemoryArray(),
                roleAccounts,
                DEFAULT_SWAP_FEE_WEIGHTED,
                address(0),
                false, // Do not enable donations
                false, // Do not disable unbalanced add/remove liquidity
                // NOTE: sends a unique salt.
                bytes32(poolCreationNonce++)
            )
        );
        vm.label(address(newPool), label);

        // Cannot set the pool creator directly on a standard Balancer weighted pool factory.
        vault.manualSetPoolCreator(address(newPool), lp);

        ProtocolFeeControllerMock feeController = ProtocolFeeControllerMock(address(vault.getProtocolFeeController()));
        feeController.manualSetPoolCreator(address(newPool), lp);

        return address(newPool);
    }
}
