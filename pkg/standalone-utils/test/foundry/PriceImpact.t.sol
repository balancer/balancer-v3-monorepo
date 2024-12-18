// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { TokenConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { WeightedPoolFactory } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPoolFactory.sol";
import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { WeightedPool } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPool.sol";
import { PoolMock } from "@balancer-labs/v3-vault/contracts/test/PoolMock.sol";

import { InputHelpersMock } from "../../../vault/contracts/test/InputHelpersMock.sol";
import { PriceImpact } from "../../contracts/PriceImpact.sol";

contract PriceImpactTest is BaseVaultTest {
    using CastingHelpers for address[];
    using FixedPoint for uint256;
    using ArrayHelpers for *;

    uint256 constant SWAP_FEE = 1e16; // 1%

    uint256 constant USDC_AMOUNT = 1e4 * 1e18;
    uint256 constant DAI_AMOUNT = 1e4 * 1e18;

    uint256 constant DELTA = 1e9;

    WeightedPoolFactory factory;
    WeightedPool internal weightedPool;

    PriceImpact internal priceImpactHelper;

    InputHelpersMock private immutable _inputHelpersMock;

    constructor() {
        _inputHelpersMock = new InputHelpersMock();
    }

    function setUp() public virtual override {
        BaseVaultTest.setUp();
        priceImpactHelper = new PriceImpact(IVault(address(vault)));
    }

    function createPool() internal override returns (address newPool, bytes memory poolArgs) {
        string memory poolVersion = "Pool v1";

        factory = new WeightedPoolFactory(IVault(address(vault)), 365 days, "Factory v1", poolVersion);
        TokenConfig[] memory tokens = new TokenConfig[](2);
        tokens[0].token = IERC20(dai);
        tokens[1].token = IERC20(usdc);

        PoolRoleAccounts memory poolRoleAccounts;
        string memory name = "ERC20 Pool";
        string memory symbol = "ERC20POOL";
        uint256[] memory weights = [uint256(50e16), uint256(50e16)].toMemoryArray();

        weightedPool = WeightedPool(
            factory.create(
                name,
                symbol,
                _inputHelpersMock.sortTokenConfig(tokens),
                weights,
                poolRoleAccounts,
                SWAP_FEE,
                address(0),
                false,
                false,
                ZERO_BYTES32
            )
        );

        // Reset fee to 0.
        vault.manualSetAggregateSwapFeePercentage(address(weightedPool), 0);

        newPool = address(weightedPool);

        poolArgs = abi.encode(
            WeightedPool.NewPoolParams({
                name: name,
                symbol: symbol,
                numTokens: tokens.length,
                normalizedWeights: weights,
                version: poolVersion
            }),
            vault
        );
    }

    function initPool() internal override {
        uint256[] memory amountsIn = [uint256(DAI_AMOUNT), uint256(USDC_AMOUNT)].toMemoryArray();
        vm.prank(lp);
        router.initialize(
            pool,
            InputHelpers.sortTokens([address(dai), address(usdc)].toMemoryArray().asIERC20()),
            amountsIn,
            // Account for the precision loss
            DAI_AMOUNT - DELTA - 1e6,
            false,
            bytes("")
        );
    }

    function testPriceImpact() public {
        vm.startPrank(address(0), address(0));

        // calculate spotPrice
        uint256 infinitesimalAmountIn = 1e18;
        uint256 infinitesimalBptOut = priceImpactHelper.queryAddLiquidityUnbalanced(
            pool,
            [infinitesimalAmountIn, 0].toMemoryArray(),
            0,
            bytes("")
        );
        uint256 spotPrice = infinitesimalAmountIn.divDown(infinitesimalBptOut);

        // calculate priceImpact
        uint256 amountIn = DAI_AMOUNT / 4;
        uint256[] memory amountsIn = [amountIn, 0].toMemoryArray();
        uint256 priceImpact = priceImpactHelper.priceImpactForAddLiquidityUnbalanced(pool, amountsIn);

        // calculate effectivePrice
        uint256 bptOut = priceImpactHelper.queryAddLiquidityUnbalanced(pool, amountsIn, 0, bytes(""));
        uint256 effectivePrice = amountIn.divDown(bptOut);

        // calculate expectedPriceImpact for comparison
        uint256 expectedPriceImpact = effectivePrice.divDown(spotPrice) - 1e18;

        vm.stopPrank();

        // assert within acceptable bounds of +-1%
        assertLe(priceImpact, expectedPriceImpact + 0.01e18, "Price impact greater than expected");
        assertGe(priceImpact, expectedPriceImpact - 0.01e18, "Price impact smaller than expected");
    }
}
