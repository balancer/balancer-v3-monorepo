// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";

import { BalancerPoolToken } from "@balancer-labs/v3-vault/contracts/BalancerPoolToken.sol";
import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";

import { PoolMockWithDonation } from "../../contracts/test/PoolMockWithDonation.sol";

contract PoolDonationTest is BaseVaultTest {
    using ArrayHelpers for *;

    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    function setUp() public override {
        super.setUp();

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));
    }

    function _createPool(address[] memory tokens, string memory label) internal override returns (address) {
        PoolMockWithDonation newPool = new PoolMockWithDonation(IVault(address(vault)), "ERC20 Pool", "ERC20POOL");
        vm.label(address(newPool), label);

        factoryMock.registerTestPool(
            address(newPool),
            vault.buildTokenConfig(tokens.asIERC20()),
            poolHooksContract,
            address(lp)
        );

        return address(newPool);
    }

    function testUnbalancedDonationToPool() public {
        uint256 amountToDonate = poolInitAmount / 10;

        uint256[] memory amountsToDonate = new uint256[](2);
        amountsToDonate[daiIdx] = amountToDonate;

        HookTestLocals memory vars = _createHookTestLocals();

        vm.prank(bob);
        router.addLiquidityCustom(pool, amountsToDonate, 0, false, bytes(""));

        _fillAfterHookTestLocals(vars);

        // Bob balances
        assertEq(vars.bob.daiBefore - vars.bob.daiAfter, amountToDonate, "Bob DAI balance is wrong");
        assertEq(vars.bob.usdcAfter, vars.bob.usdcBefore, "Bob USDC balance is wrong");
        assertEq(vars.bob.bptAfter, vars.bob.bptBefore, "Bob BPT balance is wrong");

        // Pool balances
        assertEq(vars.poolAfter[daiIdx] - vars.poolBefore[daiIdx], amountToDonate, "Pool DAI balance is wrong");
        assertEq(vars.poolAfter[usdcIdx], vars.poolBefore[usdcIdx], "Pool USDC balance is wrong");
        assertEq(vars.bptSupplyAfter, vars.bptSupplyBefore, "Pool BPT supply is wrong");

        // Vault Balances
        assertEq(vars.vault.daiAfter - vars.vault.daiBefore, amountToDonate, "Vault DAI balance is wrong");
        assertEq(vars.vault.usdcAfter, vars.vault.usdcBefore, "Vault USDC balance is wrong");
    }

    struct WalletState {
        uint256 daiBefore;
        uint256 daiAfter;
        uint256 usdcBefore;
        uint256 usdcAfter;
        uint256 bptBefore;
        uint256 bptAfter;
    }

    struct HookTestLocals {
        WalletState bob;
        WalletState hook;
        WalletState vault;
        uint256[] poolBefore;
        uint256[] poolAfter;
        uint256 bptSupplyBefore;
        uint256 bptSupplyAfter;
    }

    function _createHookTestLocals() private returns (HookTestLocals memory vars) {
        vars.bob.daiBefore = dai.balanceOf(address(bob));
        vars.bob.usdcBefore = usdc.balanceOf(address(bob));
        vars.bob.bptBefore = IERC20(pool).balanceOf(address(bob));
        vars.vault.daiBefore = dai.balanceOf(address(vault));
        vars.vault.usdcBefore = usdc.balanceOf(address(vault));
        vars.poolBefore = vault.getRawBalances(pool);
        vars.bptSupplyBefore = BalancerPoolToken(pool).totalSupply();
    }

    function _fillAfterHookTestLocals(HookTestLocals memory vars) private {
        vars.bob.daiAfter = dai.balanceOf(address(bob));
        vars.bob.usdcAfter = usdc.balanceOf(address(bob));
        vars.bob.bptAfter = IERC20(pool).balanceOf(address(bob));
        vars.vault.daiAfter = dai.balanceOf(address(vault));
        vars.vault.usdcAfter = usdc.balanceOf(address(vault));
        vars.poolAfter = vault.getRawBalances(pool);
        vars.bptSupplyAfter = BalancerPoolToken(pool).totalSupply();
    }
}
