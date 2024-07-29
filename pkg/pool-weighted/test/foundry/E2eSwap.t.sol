// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IProtocolFeeController } from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeeController.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";

import { PoolHooksMock } from "@balancer-labs/v3-vault/contracts/test/PoolHooksMock.sol";
import { ProtocolFeeControllerMock } from "@balancer-labs/v3-vault/contracts/test/ProtocolFeeControllerMock.sol";
import { E2eSwapTest } from "@balancer-labs/v3-vault/test/foundry/E2eSwap.t.sol";

import { WeightedPoolFactory } from "../../contracts/WeightedPoolFactory.sol";
import { WeightedPool } from "../../contracts/WeightedPool.sol";

contract E2eSwapWeightedTest is E2eSwapTest {
    using ArrayHelpers for *;

    uint256 internal constant DEFAULT_SWAP_FEE = 1e16; // 1%

    uint256 internal poolCreationNonce;

    function setUp() public override {
        E2eSwapTest.setUp();
    }

    function _setUpVariables() internal override {
        token1 = dai;
        token2 = usdc;
        sender = lp;
        poolCreator = lp;

        // If there are swap fees, the amountCalculated may be lower than MIN_TRADE_AMOUNT. So, multiplying
        // MIN_TRADE_AMOUNT by 1e4 creates a margin (especially for operations in the edge of the price curve).
        minSwapAmountToken1 = 1e4 * MIN_TRADE_AMOUNT;
        minSwapAmountToken2 = 1e4 * MIN_TRADE_AMOUNT;

        // Divide init amount by 10 to make sure weighted math ratios are respected (Cannot trade more than 30% of pool
        // balance).
        maxSwapAmountToken1 = poolInitAmount / 10;
        maxSwapAmountToken2 = poolInitAmount / 10;

        // 0.0001% max swap fee.
        minPoolSwapFeePercentage = 1e12;
        // 10% max swap fee.
        maxPoolSwapFeePercentage = 1e17;
    }

    /**
     * @notice Overrides BaseVaultTest _createPool().
     */
    function _createPool(address[] memory tokens, string memory label) internal override returns (address) {
        WeightedPoolFactory factory = new WeightedPoolFactory(
            IVault(address(vault)),
            365 days,
            "Factory v1",
            "Pool v1"
        );
        PoolRoleAccounts memory roleAccounts;

        // Allow pools created by `factory` to use poolHooksMock hooks
        PoolHooksMock(poolHooksContract).allowFactory(address(factory));

        WeightedPool newPool = WeightedPool(
            factory.create(
                "ERC20 Pool",
                "ERC20POOL",
                vault.buildTokenConfig(tokens.asIERC20()),
                [uint256(50e16), uint256(50e16)].toMemoryArray(),
                roleAccounts,
                DEFAULT_SWAP_FEE, // 1% swap fee, but test will override it.
                poolHooksContract,
                false, // Do not enable donations
                false, // Do not disable unbalanced add/remove liquidity
                // NOTE: sends a unique salt
                bytes32(poolCreationNonce++)
            )
        );
        vm.label(address(newPool), label);

        // Cannot set pool creator directly with stable pool factory.
        vault.manualSetPoolCreator(address(newPool), lp);

        ProtocolFeeControllerMock feeController = ProtocolFeeControllerMock(address(vault.getProtocolFeeController()));
        feeController.manualSetPoolCreator(address(newPool), lp);

        return address(newPool);
    }
}
