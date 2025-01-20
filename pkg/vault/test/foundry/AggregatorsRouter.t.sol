// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IRateProvider.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { TokenConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IRouterSwap } from "@balancer-labs/v3-interfaces/contracts/vault/IRouterSwap.sol";
import { IRouterPaymentHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IRouterPaymentHooks.sol";

import { EVMCallModeHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/EVMCallModeHelpers.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";

import { RateProviderMock } from "../../contracts/test/RateProviderMock.sol";
import { AggregatorsRouter } from "../../contracts/AggregatorsRouter.sol";
import { AggregatorMock } from "../../contracts/test/AggregatorMock.sol";
import { PoolMock } from "../../contracts/test/PoolMock.sol";

import { PoolFactoryMock, BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract AggregatorsRouterTest is BaseVaultTest {
    using CastingHelpers for address[];
    using ArrayHelpers for *;

    string version = "test";
    AggregatorsRouter internal aggregatorsRouter;
    AggregatorMock internal aggregatorMock;

    uint256 aggregatorUDCInitialBalance;
    uint256 aggregatorDAIInitialBalance;

    // Track the indices for the standard dai/usdc pool.
    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    function setUp() public virtual override {
        rateProvider = deployRateProviderMock();

        BaseVaultTest.setUp();
        aggregatorsRouter = deployAggregatorsRouter(IVault(address(vault)), weth, version);
        aggregatorMock = new AggregatorMock(address(vault), IRouterSwap(address(aggregatorsRouter)));

        uint256 aliceBalance = usdc.balanceOf(alice);
        aggregatorUDCInitialBalance = aliceBalance;
        aggregatorDAIInitialBalance = 0;
        vm.prank(alice);
        usdc.transfer(address(aggregatorMock), aliceBalance);
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
        aggregatorMock.setPaymentHookActive(false);

        vm.prank(alice);
        vm.expectRevert(IVaultErrors.BalanceNotSettled.selector);
        aggregatorMock.swapSingleTokenExactIn(address(pool), usdc, dai, 1e18, 0, MAX_UINT256, false, bytes(""));
    }

    function testSwapExactIn_Fuzz(uint256 swapAmount) public {
        swapAmount = bound(swapAmount, 1e18, vault.getPoolData(address(pool)).balancesLiveScaled18[daiIdx]);

        vm.prank(alice);
        uint256 outputTokenAmount = aggregatorMock.swapSingleTokenExactIn(
            address(pool),
            usdc,
            dai,
            swapAmount,
            0,
            MAX_UINT256,
            false,
            bytes("")
        );
        assertEq(
            usdc.balanceOf(address(aggregatorMock)),
            aggregatorUDCInitialBalance - swapAmount,
            "Wrong usdc balance"
        );
        assertEq(
            dai.balanceOf(address(aggregatorMock)),
            aggregatorDAIInitialBalance + outputTokenAmount,
            "Wrong dai balance"
        );
    }

    function testSwapExactOut_Fuzz(uint256 swapAmount) public {
        swapAmount = bound(swapAmount, 1e18, vault.getPoolData(address(pool)).balancesLiveScaled18[daiIdx]);

        uint256 snapshotId = vm.snapshot();

        _prankStaticCall();
        uint256 exactAmountOut = router.querySwapSingleTokenExactIn(
            pool,
            usdc,
            dai,
            swapAmount,
            address(this),
            bytes("")
        );
        vm.revertTo(snapshotId);

        vm.prank(alice);
        uint256 amountIn = aggregatorMock.swapSingleTokenExactOut(
            address(pool),
            usdc,
            dai,
            exactAmountOut,
            MAX_UINT256,
            MAX_UINT256,
            false,
            bytes("")
        );

        assertEq(usdc.balanceOf(address(aggregatorMock)), aggregatorUDCInitialBalance - amountIn, "Wrong usdc balance");
        assertEq(
            dai.balanceOf(address(aggregatorMock)),
            aggregatorDAIInitialBalance + exactAmountOut,
            "Wrong dai balance"
        );
    }

    function testRouterVersion() public view {
        assertEq(aggregatorsRouter.version(), version, "Router version mismatch");
    }
}
