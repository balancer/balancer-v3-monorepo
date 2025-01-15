// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { TokenConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { EVMCallModeHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/EVMCallModeHelpers.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";

import { RateProviderMock } from "../../contracts/test/RateProviderMock.sol";
import { AggregatorsRouter } from "../../contracts/AggregatorsRouter.sol";
import { PoolMock } from "../../contracts/test/PoolMock.sol";

import { PoolFactoryMock, BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract AggregatorsRouterTest is BaseVaultTest {
    using CastingHelpers for address[];
    using ArrayHelpers for *;

    string version = "test";
    AggregatorsRouter internal aggregatorsRouter;

    // Track the indices for the standard dai/usdc pool.
    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    function setUp() public virtual override {
        rateProvider = deployRateProviderMock();

        BaseVaultTest.setUp();
        aggregatorsRouter = deployAggregatorsRouter(IVault(address(vault)), version);
    }

    function createPool() internal override returns (address newPool, bytes memory poolArgs) {
        string memory name = "ERC20 Pool";
        string memory symbol = "ERC20POOL";

        newPool = address(deployPoolMock(IVault(address(vault)), name, symbol));
        vm.label(newPool, "pool");

        IRateProvider[] memory rateProviders = new IRateProvider[](2);
        rateProviders[0] = rateProvider;
        rateProviders[1] = rateProvider;
        bool[] memory paysYieldFees = new bool[](2);
        paysYieldFees[0] = true;
        paysYieldFees[1] = true;

        PoolFactoryMock(poolFactory).registerTestPool(
            newPool,
            vault.buildTokenConfig(
                [address(dai), address(usdc)].toMemoryArray().asIERC20(),
                rateProviders,
                paysYieldFees
            ),
            poolHooksContract,
            lp
        );
        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));

        poolArgs = abi.encode(vault, name, symbol);
    }

    function testQuerySwap() public {
        vm.prank(bob);
        vm.expectRevert(EVMCallModeHelpers.NotStaticCall.selector);
        aggregatorsRouter.querySwapSingleTokenExactIn(pool, usdc, dai, 1e18, address(this), bytes(""));
    }

    function testSwapExactInWithoutPayment() public {
        vm.prank(alice);
        vm.expectRevert(IVaultErrors.BalanceNotSettled.selector);
        aggregatorsRouter.swapSingleTokenExactIn(address(pool), usdc, dai, 1e18, 0, MAX_UINT256, bytes(""));
    }

    function testSwapExactIn__Fuzz(uint256 swapAmount) public {
        swapAmount = bound(swapAmount, 1e18, vault.getPoolData(address(pool)).balancesLiveScaled18[daiIdx]);

        vm.startPrank(alice);
        usdc.transfer(address(vault), swapAmount);

        uint256 outputTokenAmount = aggregatorsRouter.swapSingleTokenExactIn(
            address(pool),
            usdc,
            dai,
            swapAmount,
            0,
            MAX_UINT256,
            bytes("")
        );
        vm.stopPrank();

        assertEq(usdc.balanceOf(alice), defaultAccountBalance() - swapAmount, "Wrong USDC balance");
        assertEq(dai.balanceOf(alice), defaultAccountBalance() + outputTokenAmount, "Wrong DAI balance");
    }

    function testRouterVersion() public view {
        assertEq(aggregatorsRouter.version(), version, "Router version mismatch");
    }
}
