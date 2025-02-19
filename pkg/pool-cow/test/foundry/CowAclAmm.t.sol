// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { console2 } from "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";
import { WeightedPool } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPool.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { CowAclAmm } from "../../contracts/CowAclAmm.sol";
import { CowAclAmmFactory } from "../../contracts/CowAclAmmFactory.sol";
import { CowRouter } from "../../contracts/CowRouter.sol";
import { CowPoolContractsDeployer } from "./utils/CowPoolContractsDeployer.sol";

contract CowAclAmmTest is CowPoolContractsDeployer, BaseVaultTest {
    using ArrayHelpers for *;
    using CastingHelpers for address[];
    using FixedPoint for uint256;

    uint256 internal constant _DEFAULT_SWAP_FEE = 1e16; // 1%
    string internal constant _POOL_VERSION = "CoW Pool v1";

    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    address internal feeSweeper;
    CowRouter internal cowRouter;

    function createPoolFactory() internal override returns (address) {
        // Set fee sweeper before the router is created.
        feeSweeper = bob;

        // Creates cowRouter before the factory, so we have an address to set as trusted router.
        cowRouter = deployCowPoolRouter(vault, 10e16, feeSweeper);

        CowAclAmmFactory cowFactory = new CowAclAmmFactory(
            IVault(address(vault)),
            365 days,
            "Factory v1",
            _POOL_VERSION,
            address(cowRouter)
        );
        vm.label(address(cowFactory), "CoW ACL AMM Factory");

        return address(cowFactory);
    }

    function _createPool(
        address[] memory tokens,
        string memory label
    ) internal override returns (address newPool, bytes memory poolArgs) {
        string memory name = "Cow AMM Pool";
        string memory symbol = "COWPOOL";
        uint256[] memory weights = [uint256(50e16), uint256(50e16)].toMemoryArray();

        IERC20[] memory sortedTokens = InputHelpers.sortTokens(tokens.asIERC20());

        PoolRoleAccounts memory roleAccounts;

        newPool = CowAclAmmFactory(poolFactory).create(
            name,
            symbol,
            vault.buildTokenConfig(sortedTokens),
            weights,
            roleAccounts,
            _DEFAULT_SWAP_FEE,
            1.4e18, // PriceRange = 4 (Example ETH/USDC 1000 - 4000)
            10e16, // Margin 10%
            100e16, // Increase per day 100%
            ZERO_BYTES32
        );
        vm.label(newPool, label);

        // poolArgs is used to check pool deployment address with create2.
        poolArgs = abi.encode(
            WeightedPool.NewPoolParams({
                name: name,
                symbol: symbol,
                numTokens: sortedTokens.length,
                normalizedWeights: weights,
                version: _POOL_VERSION
            }),
            vault,
            poolFactory,
            router
        );

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));
    }

    function testAclAmm() public {
        (, , uint256[] memory balances, ) = vault.getPoolTokenInfo(pool);
        (uint256[] memory virtualBalances, bool changed) = CowAclAmm(pool).getVirtualBalances(balances, false);

        console2.log("initialBalances[daiIdx]     ", balances[daiIdx]);
        console2.log("initialBalances[usdcIdx]    ", balances[usdcIdx]);

        console2.log("virtualBalances[daiIdx]     ", virtualBalances[daiIdx]);
        console2.log("virtualBalances[usdcIdx]    ", virtualBalances[usdcIdx]);

        assertFalse(changed);

        uint256[] memory newBalances = new uint256[](2);
        newBalances[daiIdx] = 0;
        newBalances[usdcIdx] = 2400e18;
        vault.manualSetPoolBalances(pool, newBalances, newBalances);

        (uint256[] memory newVirtualBalances, bool newChanged) = CowAclAmm(pool).getVirtualBalances(newBalances, false);

        assertTrue(newChanged);

        console2.log("newBalances[daiIdx]         ", newBalances[daiIdx]);
        console2.log("newBalances[usdcIdx]        ", newBalances[usdcIdx]);

        console2.log("newVirtualBalances[daiIdx]  ", newVirtualBalances[daiIdx]);
        console2.log("newVirtualBalances[usdcIdx] ", newVirtualBalances[usdcIdx]);

        vm.warp(block.timestamp + 1 days);

        (uint256[] memory newVirtualBalances2, ) = CowAclAmm(pool).getVirtualBalances(newBalances, false);

        console2.log("AFTER 1 DAY");
        console2.log("newVirtualBalances2[daiIdx] ", newVirtualBalances2[daiIdx]);
        console2.log("newVirtualBalances2[usdcIdx]", newVirtualBalances2[usdcIdx]);

        // Simulate swap exact in to leave pool 50/50 balanced.
        uint256 newBalanceUsdc = 0;
        uint256 newBalanceDai = newVirtualBalances2[daiIdx]
            .mulDown(newBalances[usdcIdx] + newVirtualBalances2[usdcIdx])
            .divDown(newVirtualBalances2[usdcIdx] + newBalanceUsdc) - newVirtualBalances2[daiIdx];
        newBalances[daiIdx] = newBalanceDai;
        newBalances[usdcIdx] = newBalanceUsdc;

        console2.log("AFTER SWAP");
        console2.log("newBalances2[daiIdx]        ", newBalances[daiIdx]);
        console2.log("newBalances2[usdcIdx]       ", newBalances[usdcIdx]);

        CowAclAmm(pool).setVirtualBalances(newVirtualBalances2);
        CowAclAmm(pool).setLastTimestamp(block.timestamp);
        CowAclAmm(pool).setLastInvariant(newBalances);
        vault.manualSetPoolBalances(pool, newBalances, newBalances);

        // Accomodate pool in the new range (recalculate lastTimestamp and lastInvariant).
        CowAclAmm(pool).updateVirtualBalances(newBalances);

        (uint256[] memory newVirtualBalances3, ) = CowAclAmm(pool).getVirtualBalances(newBalances, false);

        console2.log("NEW VIRTUAL BALANCES");
        console2.log("newVirtualBalances3[daiIdx] ", newVirtualBalances3[daiIdx]);
        console2.log("newVirtualBalances3[usdcIdx]", newVirtualBalances3[usdcIdx]);

        vm.warp(block.timestamp + 1 days);

        (uint256[] memory newVirtualBalances4, ) = CowAclAmm(pool).getVirtualBalances(newBalances, false);

        console2.log("AFTER 1 DAY");
        console2.log("newVirtualBalances4[daiIdx] ", newVirtualBalances4[daiIdx]);
        console2.log("newVirtualBalances4[usdcIdx]", newVirtualBalances4[usdcIdx]);
    }
}
