// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { StableMath } from "@balancer-labs/v3-solidity-utils/contracts/math/StableMath.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { StablePoolContractsDeployer } from "./utils/StablePoolContractsDeployer.sol";
import { StablePoolFactory } from "../../contracts/StablePoolFactory.sol";
import { StablePool } from "../../contracts/StablePool.sol";

contract ImbalanceTest is StablePoolContractsDeployer, BaseVaultTest {
    using FixedPoint for uint256;
    using ArrayHelpers for *;
    using CastingHelpers for *;

    uint256 private constant MAX_IMBALANCE_RATIO = 10_000e18;
    uint256 private constant DEFAULT_TOKEN_IN_INDEX = 0;
    uint256 private constant DEFAULT_TOKEN_OUT_INDEX = 1;
    uint256 private constant DEFAULT_AMP_FACTOR = 200;
    uint256 private constant SWAP_FEE_PERCENTAGE = 10e16; // 10%
    string private constant POOL_VERSION = "Pool v1";

    function setUp() public override {
        BaseVaultTest.setUp();
    }

    function createPoolFactory() internal override returns (address) {
        return address(deployStablePoolFactory(IVault(address(vault)), 365 days, "Factory v1", POOL_VERSION));
    }

    function _createPool(
        address[] memory tokens,
        string memory label
    ) internal override returns (address newPool, bytes memory poolArgs) {
        string memory name = "Stable Pool";
        string memory symbol = "STABLE";

        PoolRoleAccounts memory roleAccounts;

        bytes32 salt = keccak256(abi.encode(label));
        newPool = StablePoolFactory(poolFactory).create(
            name,
            symbol,
            vault.buildTokenConfig(tokens.asIERC20()),
            DEFAULT_AMP_FACTOR,
            roleAccounts,
            SWAP_FEE_PERCENTAGE,
            address(0),
            false, // Do not enable donations
            false, // Do not disable unbalanced add/remove liquidity
            salt
        );
        vm.label(address(newPool), label);

        poolArgs = abi.encode(
            StablePool.NewPoolParams({
                name: name,
                symbol: symbol,
                amplificationParameter: DEFAULT_AMP_FACTOR,
                version: POOL_VERSION
            }),
            vault
        );
    }

    function testOnSwapExactIn() public {
        uint256[] memory balancesScaled18 = new uint256[](2);
        balancesScaled18[0] = MAX_IMBALANCE_RATIO - 1;
        balancesScaled18[1] = 1e18;
        uint256 amountIn = 100e18;

        _testOnSwapExactIn(balancesScaled18, amountIn, DEFAULT_TOKEN_IN_INDEX, DEFAULT_TOKEN_OUT_INDEX);
    }

    function testOnSwapExactInWithThreeTokensNewMax() public {
        uint256[] memory balancesScaled18 = new uint256[](3);
        balancesScaled18[0] = MAX_IMBALANCE_RATIO - 1;
        balancesScaled18[1] = 2e18;
        balancesScaled18[2] = 1e18;
        uint256 amountIn = 1e6;
        uint256 tokenInIndex = 0;
        uint256 tokenOutIndex = 1;

        // Breaks ratio between 0 and 2 by enlarging balance 0 (max balance).
        _testOnSwapExactIn(balancesScaled18, amountIn, tokenInIndex, tokenOutIndex);
    }

    function testOnSwapExactInWithThreeTokensNewMin() public {
        uint256[] memory balancesScaled18 = new uint256[](3);
        balancesScaled18[0] = MAX_IMBALANCE_RATIO - 1;
        balancesScaled18[1] = 2e18;
        balancesScaled18[2] = 1e18;
        uint256 amountIn = 1e6;
        uint256 tokenInIndex = 1;
        uint256 tokenOutIndex = 2;

        // Breaks ratio between 0 and 2 by shrinking balance 2 (min balance).
        _testOnSwapExactIn(balancesScaled18, amountIn, tokenInIndex, tokenOutIndex);
    }

    function testOnSwapExactOut() public {
        uint256[] memory balancesScaled18 = new uint256[](2);
        balancesScaled18[0] = MAX_IMBALANCE_RATIO - 1;
        balancesScaled18[1] = 1e18;
        uint256 amountOut = 0.1e18;
        uint256 tokenInIndex = 0;
        uint256 tokenOutIndex = 1;

        _testOnSwapExactOut(balancesScaled18, amountOut, tokenInIndex, tokenOutIndex);
    }

    function testOnSwapExactOutWithThreeTokensNewMax() public {
        uint256[] memory balancesScaled18 = new uint256[](3);
        balancesScaled18[0] = MAX_IMBALANCE_RATIO - 1;
        balancesScaled18[1] = 2e18;
        balancesScaled18[2] = 1e18;
        uint256 amountOut = 0.1e18;
        uint256 tokenInIndex = 0;
        uint256 tokenOutIndex = 1;

        // Breaks ratio between 0 and 2 by enlarging balance 0 (max balance).
        _testOnSwapExactOut(balancesScaled18, amountOut, tokenInIndex, tokenOutIndex);
    }

    function testOnSwapExactOutWithThreeTokensNewMin() public {
        uint256[] memory balancesScaled18 = new uint256[](3);
        balancesScaled18[0] = MAX_IMBALANCE_RATIO - 1;
        balancesScaled18[1] = 1e18;
        balancesScaled18[2] = 1e18;
        uint256 amountOut = 0.1e18;
        uint256 tokenInIndex = 1;
        uint256 tokenOutIndex = 2;

        // Breaks ratio between 0 and 2 by shrinking balance 2 (min balance).
        _testOnSwapExactOut(balancesScaled18, amountOut, tokenInIndex, tokenOutIndex);
    }

    function testComputeInvariant() public {
        uint256[] memory balancesScaled18 = new uint256[](2);
        balancesScaled18[0] = 1e18;
        balancesScaled18[1] = MAX_IMBALANCE_RATIO;

        vm.expectRevert(StableMath.MaxImbalanceRatioExceeded.selector);
        StablePool(pool).computeInvariant(balancesScaled18, Rounding.ROUND_DOWN);
    }

    function testComputeBalance() public {
        uint256[] memory balancesScaled18 = new uint256[](2);
        balancesScaled18[0] = 1e18;
        balancesScaled18[1] = 1e18;

        // Does not revert with current balances.
        (uint256 minBalance, uint256 maxBalance) = StableMath.getMinAndMaxBalances(balancesScaled18);
        StableMath.ensureBalancesWithinMaxImbalanceRange(minBalance, maxBalance);

        uint256 invariantRatio = MAX_IMBALANCE_RATIO;
        vm.expectRevert(StableMath.MaxImbalanceRatioExceeded.selector);
        StablePool(pool).computeBalance(balancesScaled18, DEFAULT_TOKEN_IN_INDEX, invariantRatio);
    }

    function testComputeBalanceNewMax() public {
        uint256[] memory balancesScaled18 = new uint256[](3);
        balancesScaled18[0] = MAX_IMBALANCE_RATIO - 1;
        balancesScaled18[1] = 1e18;
        balancesScaled18[2] = 1e18;

        // Does not revert with current balances.
        (uint256 minBalance, uint256 maxBalance) = StableMath.getMinAndMaxBalances(balancesScaled18);
        StableMath.ensureBalancesWithinMaxImbalanceRange(minBalance, maxBalance);

        uint256 invariantRatio = 1.1e18;
        uint256 tokenIndex = 0;
        vm.expectRevert(StableMath.MaxImbalanceRatioExceeded.selector);
        StablePool(pool).computeBalance(balancesScaled18, tokenIndex, invariantRatio);
    }

    function testComputeBalanceNewMin() public {
        uint256[] memory balancesScaled18 = new uint256[](3);
        balancesScaled18[0] = MAX_IMBALANCE_RATIO - 1;
        balancesScaled18[1] = 1e18;
        balancesScaled18[2] = 1e18;

        // Does not revert with current balances.
        (uint256 minBalance, uint256 maxBalance) = StableMath.getMinAndMaxBalances(balancesScaled18);
        StableMath.ensureBalancesWithinMaxImbalanceRange(minBalance, maxBalance);

        uint256 invariantRatio = 0.9e18;
        uint256 tokenIndex = 1;
        vm.expectRevert(StableMath.MaxImbalanceRatioExceeded.selector);
        StablePool(pool).computeBalance(balancesScaled18, tokenIndex, invariantRatio);
    }

    function _testOnSwapExactIn(
        uint256[] memory balancesScaled18,
        uint256 amountGivenScaled18,
        uint256 tokenInIndex,
        uint256 tokenOutIndex
    ) internal {
        // Does not revert with current balances.
        (uint256 minBalance, uint256 maxBalance) = StableMath.getMinAndMaxBalances(balancesScaled18);
        StableMath.ensureBalancesWithinMaxImbalanceRange(minBalance, maxBalance);

        PoolSwapParams memory params = PoolSwapParams({
            kind: SwapKind.EXACT_IN,
            amountGivenScaled18: amountGivenScaled18,
            balancesScaled18: balancesScaled18,
            indexIn: tokenInIndex,
            indexOut: tokenOutIndex,
            router: address(0),
            userData: bytes("")
        });

        vm.expectRevert(StableMath.MaxImbalanceRatioExceeded.selector);
        StablePool(pool).onSwap(params);
    }

    function _testOnSwapExactOut(
        uint256[] memory balancesScaled18,
        uint256 amountGivenScaled18,
        uint256 tokenInIndex,
        uint256 tokenOutIndex
    ) internal {
        // Does not revert with current balances.
        (uint256 minBalance, uint256 maxBalance) = StableMath.getMinAndMaxBalances(balancesScaled18);
        StableMath.ensureBalancesWithinMaxImbalanceRange(minBalance, maxBalance);

        PoolSwapParams memory params = PoolSwapParams({
            kind: SwapKind.EXACT_OUT,
            amountGivenScaled18: amountGivenScaled18,
            balancesScaled18: balancesScaled18,
            indexIn: tokenInIndex,
            indexOut: tokenOutIndex,
            router: address(0),
            userData: bytes("")
        });

        vm.expectRevert(StableMath.MaxImbalanceRatioExceeded.selector);
        StablePool(pool).onSwap(params);
    }
}
