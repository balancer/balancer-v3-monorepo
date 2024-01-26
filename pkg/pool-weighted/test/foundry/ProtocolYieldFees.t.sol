// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { TokenConfig, TokenType, PoolConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { WeightedPoolFactory } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPoolFactory.sol";
import { WeightedPool } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPool.sol";
import { RateProviderMock } from "@balancer-labs/v3-vault/contracts/test/RateProviderMock.sol";

import { BaseVaultTest } from "vault/test/foundry/utils/BaseVaultTest.sol";

contract ProtocolYieldFeesTest is BaseVaultTest {
    using ArrayHelpers for *;
    
    uint256 constant DELTA = 1e9;

    WeightedPoolFactory internal factory;
    WeightedPool internal weightedPool;
    
    RateProviderMock wstETHRateProvider;
    RateProviderMock daiRateProvider;

    uint256 bptAmountOut;

    function setUp() public virtual override {
        BaseVaultTest.setUp();
    }

    function createPool() internal override returns (address) {
        factory = new WeightedPoolFactory(IVault(address(vault)), 365 days);
        wstETHRateProvider = new RateProviderMock();
        daiRateProvider = new RateProviderMock();

        // Initialize both tokens with a rate, and make the second one yield exempt
        TokenConfig[] memory tokens = new TokenConfig[](2);
        tokens[0].token = IERC20(wsteth);
        tokens[0].tokenType = TokenType.WITH_RATE;
        tokens[0].rateProvider = IRateProvider(wstETHRateProvider);

        tokens[1].token = IERC20(dai);
        tokens[1].tokenType = TokenType.WITH_RATE;
        tokens[1].rateProvider = IRateProvider(daiRateProvider);
        tokens[1].yieldFeeExempt = true;

        weightedPool = WeightedPool(
            factory.create(
                "ERC20 Pool",
                "ERC20POOL",
                tokens,
                [uint256(0.50e18), uint256(0.50e18)].toMemoryArray(),
                ZERO_BYTES32
            )
        );

        return address(weightedPool);
    }

    function initPool() internal override {
        uint256[] memory amountsIn = [uint256(defaultAmount), uint256(defaultAmount)].toMemoryArray();
        vm.prank(lp);
        bptAmountOut = router.initialize(
            pool,
            [address(wsteth), address(dai)].toMemoryArray().asIERC20(),
            amountsIn,
            // Account for the precision loss
            defaultAmount - DELTA - 1e6,
            false,
            bytes("")
        );
    }

    function testInitializeWeightedPool() public {
        // Tokens are transferred from lp
        assertEq(defaultBalance - wsteth.balanceOf(lp), defaultAmount);
        assertEq(defaultBalance - dai.balanceOf(lp), defaultAmount);

        // Tokens are stored in the Vault
        assertEq(wsteth.balanceOf(address(vault)), defaultAmount);
        assertEq(dai.balanceOf(address(vault)), defaultAmount);

        // Tokens are deposited to the pool
        (, , uint256[] memory balances, , ) = vault.getPoolTokenInfo(address(pool));
        assertEq(balances[0], defaultAmount);
        assertEq(balances[1], defaultAmount);

        // should mint correct amount of BPT tokens
        // Account for the precision loss
        assertApproxEqAbs(weightedPool.balanceOf(lp), bptAmountOut, DELTA);
        assertApproxEqAbs(bptAmountOut, defaultAmount, DELTA);
    }
}
