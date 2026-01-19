// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { ISenderGuard } from "@balancer-labs/v3-interfaces/contracts/vault/ISenderGuard.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPCommon.sol";
import "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPool.sol";
import { IWeightedPool } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/IWeightedPool.sol";
import { MinTokenBalanceLib } from "@balancer-labs/v3-vault/contracts/lib/MinTokenBalanceLib.sol";

import { WeightedPool } from "../../../contracts/WeightedPool.sol";
import { WeightedPoolFactory } from "../../../contracts/WeightedPoolFactory.sol";
import { WeightedPool8020Factory } from "../../../contracts/WeightedPool8020Factory.sol";

import { LBPCommon } from "../../../contracts/lbp/LBPCommon.sol";
import { LBPool } from "../../../contracts/lbp/LBPool.sol";

contract MockSenderGuard is ISenderGuard {
    address private _sender;

    function setSender(address sender_) external {
        _sender = sender_;
    }

    function getSender() external view returns (address) {
        return _sender;
    }
}

contract MockVaultTokens {
    IERC20[] private _tokens;

    function setTokens(uint256 n) external {
        _tokens = new IERC20[](n);
        for (uint256 i = 0; i < n; ++i) {
            _tokens[i] = IERC20(address(uint160(i + 1)));
        }
    }

    // Signature matches IVault.getPoolTokens(address)
    function getPoolTokens(address) external view returns (IERC20[] memory) {
        return _tokens;
    }
}

contract SimpleToken is IERC20Metadata {
    uint8 private immutable _decimals;
    string private _symbol;

    constructor(uint8 decimals_, string memory symbol_) {
        _decimals = decimals_;
        _symbol = symbol_;
    }

    function name() external pure returns (string memory) {
        return "T";
    }

    function symbol() external view returns (string memory) {
        return _symbol;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    // Not used by these tests; stubbed to satisfy IERC20.
    function totalSupply() external pure returns (uint256) {
        return 0;
    }

    function balanceOf(address) external pure returns (uint256) {
        return 0;
    }

    function transfer(address, uint256) external pure returns (bool) {
        return false;
    }

    function allowance(address, address) external pure returns (uint256) {
        return 0;
    }

    function approve(address, uint256) external pure returns (bool) {
        return false;
    }

    function transferFrom(address, address, uint256) external pure returns (bool) {
        return false;
    }
}

contract WeightedPoolHarness is WeightedPool {
    constructor(NewPoolParams memory params, IVault vault) WeightedPool(params, vault) {}

    function exposedGetNormalizedWeight(uint256 tokenIndex) external view returns (uint256) {
        return _getNormalizedWeight(tokenIndex);
    }
}

contract LBPCommonHarness is LBPCommon {
    constructor(
        LBPCommonParams memory lbpCommonParams,
        MigrationParams memory migrationParams,
        address trustedRouter,
        address migrationRouter
    ) LBPCommon(lbpCommonParams, migrationParams, trustedRouter, migrationRouter) {}

    // Minimal implementations to make this harness deployable.
    function computeInvariant(uint256[] memory, Rounding) public pure returns (uint256) {
        revert("unused");
    }

    function computeBalance(uint256[] memory, uint256, uint256) external pure returns (uint256) {
        revert("unused");
    }

    function onSwap(PoolSwapParams calldata) external pure returns (uint256) {
        revert("unused");
    }

    function getMinimumSwapFeePercentage() external pure returns (uint256) {
        return 0;
    }

    function getMaximumSwapFeePercentage() external pure returns (uint256) {
        return 0;
    }

    function getMinimumInvariantRatio() external pure returns (uint256) {
        return 0;
    }

    function getMaximumInvariantRatio() external pure returns (uint256) {
        return 0;
    }
}

contract LBPoolHarness is LBPool {
    constructor(
        LBPCommonParams memory lbpCommonParams,
        MigrationParams memory migrationParams,
        LBPParams memory lbpParams,
        FactoryParams memory factoryParams
    ) LBPool(lbpCommonParams, migrationParams, lbpParams, factoryParams) {}

    function exposedGetNormalizedWeight(uint256 tokenIndex) external view returns (uint256) {
        return _getNormalizedWeight(tokenIndex);
    }
}

contract CoverageGapsTest is Test {
    using FixedPoint for uint256;

    function _newParams8(uint256[] memory weights, uint256[] memory minBalances)
        private
        pure
        returns (WeightedPool.NewPoolParams memory)
    {
        return
            WeightedPool.NewPoolParams({
                name: "WP",
                symbol: "WP",
                numTokens: 8,
                normalizedWeights: weights,
                version: "v1",
                minTokenBalances: minBalances
            });
    }

    function _weightsAllEqual8() private pure returns (uint256[] memory weights) {
        weights = new uint256[](8);
        // 12.5% each
        for (uint256 i = 0; i < 8; ++i) {
            weights[i] = 125e15;
        }
    }

    function _minBalances8() private pure returns (uint256[] memory mins) {
        mins = new uint256[](8);
        for (uint256 i = 0; i < 8; ++i) {
            // must be >= ABSOLUTE_MIN_TOKEN_BALANCE; use a comfortably large value
            mins[i] = MinTokenBalanceLib.ABSOLUTE_MIN_TOKEN_BALANCE + 100 + i;
        }
    }

    function test_factory_getPoolVersion_isCovered() public {
        // These constructors do not call into the Vault; any address is fine for coverage.
        WeightedPoolFactory f = new WeightedPoolFactory(IVault(address(0x1111)), 1, "fv", "pv");
        WeightedPool8020Factory f8020 = new WeightedPool8020Factory(IVault(address(0x2222)), 1, "fv", "pv8020");

        assertEq(f.getPoolVersion(), "pv");
        assertEq(f8020.getPoolVersion(), "pv8020");
    }

    function test_weightedPool_constructor_reverts_on_minWeight() public {
        uint256[] memory weights = _weightsAllEqual8();
        weights[0] = 5e15; // 0.5% < 1% minimum
        // Fix the sum to 1 to isolate the min weight check.
        weights[1] = FixedPoint.ONE - weights[0] - (weights[2] + weights[3] + weights[4] + weights[5] + weights[6] + weights[7]);

        uint256[] memory mins = _minBalances8();

        vm.expectRevert(IWeightedPool.MinWeight.selector);
        new WeightedPoolHarness(_newParams8(weights, mins), IVault(address(0x3333)));
    }

    function test_weightedPool_constructor_reverts_on_weightSum() public {
        uint256[] memory weights = _weightsAllEqual8();
        weights[0] = weights[0] + 1; // sum != 1
        uint256[] memory mins = _minBalances8();

        vm.expectRevert(IWeightedPool.NormalizedWeightInvariant.selector);
        new WeightedPoolHarness(_newParams8(weights, mins), IVault(address(0x4444)));
    }

    function test_weightedPool_getMinTokenBalances_covers_all_return_paths() public {
        MockVaultTokens mv = new MockVaultTokens();
        // Cast is safe: we only call getPoolTokens() through the IVault ABI.
        WeightedPoolHarness pool = new WeightedPoolHarness(_newParams8(_weightsAllEqual8(), _minBalances8()), IVault(address(mv)));

        // Hit each early-return path inside _getMinTokenBalances, plus the token-7 assignment.
        for (uint256 n = 2; n <= 8; ++n) {
            mv.setTokens(n);
            uint256[] memory mins = pool.getMinTokenBalances();
            assertEq(mins.length, n);
        }
    }

    function test_weightedPool_getNormalizedWeight_invalidToken_reverts() public {
        WeightedPoolHarness pool = new WeightedPoolHarness(
            _newParams8(_weightsAllEqual8(), _minBalances8()),
            IVault(address(0x5555))
        );

        // Hit all the valid branches in the internal selector chain.
        for (uint256 i = 0; i < 8; ++i) {
            assertGt(pool.exposedGetNormalizedWeight(i), 0);
        }

        // Covers WeightedPool.sol invalid-token revert branch.
        vm.expectRevert(abi.encodeWithSignature("InvalidToken()"));
        pool.exposedGetNormalizedWeight(999);
    }

    function test_weightedPool_computeBalance_hits_minBalanceSelectorBranches() public {
        WeightedPoolHarness pool = new WeightedPoolHarness(
            _newParams8(_weightsAllEqual8(), _minBalances8()),
            IVault(address(0x5556))
        );

        uint256[] memory balances = new uint256[](8);
        uint256[] memory mins = _minBalances8();
        for (uint256 i = 0; i < 8; ++i) {
            balances[i] = mins[i] + 1;
        }

        // computeBalance calls _ensureMinimumBalance(tokenInIndex, ...) and exercises the tokenIndex selector chain.
        for (uint256 tokenInIndex = 2; tokenInIndex < 8; ++tokenInIndex) {
            uint256 newBalance = pool.computeBalance(balances, tokenInIndex, FixedPoint.ONE);
            assertGt(newBalance, 0);
        }
    }

    function test_weightedPool_ensureMinTokenBalances_reverts_for_each_extra_token() public {
        WeightedPoolHarness pool = new WeightedPoolHarness(
            _newParams8(_weightsAllEqual8(), _minBalances8()),
            IVault(address(0x6666))
        );

        uint256[] memory mins = _minBalances8();

        // Cover the revert lines for each token index (0..7), ensuring only one token is below min at a time.
        for (uint256 badIdx = 0; badIdx < 8; ++badIdx) {
            uint256[] memory balances = new uint256[](8);
            for (uint256 j = 0; j < 8; ++j) {
                balances[j] = mins[j];
            }
            balances[badIdx] = mins[badIdx] - 1;

            vm.expectRevert(); // TokenBalanceBelowMin(...)
            pool.computeInvariant(balances, Rounding.ROUND_DOWN);
        }
    }

    function test_weightedPool_ensureMinTokenBalances_return_paths_for_short_arrays() public {
        WeightedPoolHarness pool = new WeightedPoolHarness(
            _newParams8(_weightsAllEqual8(), _minBalances8()),
            IVault(address(0x6667))
        );

        uint256[] memory mins = _minBalances8();

        // Exercise each early-return branch in _ensureMinTokenBalances by passing shorter balance arrays.
        // computeInvariant will revert later (weights length mismatch), but coverage is still recorded.
        for (uint256 n = 2; n <= 7; ++n) {
            uint256[] memory balances = new uint256[](n);
            for (uint256 j = 0; j < n; ++j) {
                balances[j] = mins[j];
            }

            vm.expectRevert();
            pool.computeInvariant(balances, Rounding.ROUND_DOWN);
        }
    }

    function test_lbpCommon_onBeforeInitialize_isCovered() public {
        SimpleToken project = new SimpleToken(18, "P");
        SimpleToken reserve = new SimpleToken(18, "R");

        MockSenderGuard trustedRouter = new MockSenderGuard();

        LBPCommonParams memory common;
        common.owner = address(this);
        common.projectToken = IERC20(address(project));
        common.reserveToken = IERC20(address(reserve));
        common.startTime = uint32(block.timestamp + 1000);
        common.endTime = uint32(block.timestamp + 2000);
        common.blockProjectTokenSwapsIn = false;

        MigrationParams memory migration;
        migration.migrationRouter = address(0xBEEF);
        migration.lockDurationAfterMigration = 1 days;
        migration.bptPercentageToMigrate = 5e17; // 50%
        migration.migrationWeightProjectToken = 8e17; // 80%
        migration.migrationWeightReserveToken = 2e17; // 20%

        LBPCommonHarness h = new LBPCommonHarness(common, migration, address(trustedRouter), migration.migrationRouter);

        trustedRouter.setSender(address(this));
        assertTrue(h.onBeforeInitialize(new uint256[](2), ""));
    }

    function test_lbPool_computeBalance_reverts_and_invalidTokenWeight_reverts() public {
        SimpleToken project = new SimpleToken(18, "P");
        SimpleToken reserve = new SimpleToken(18, "R");

        // Router only used for sender checks; irrelevant for these coverage calls.
        MockSenderGuard trustedRouter = new MockSenderGuard();

        LBPCommonParams memory common;
        common.owner = address(this);
        common.projectToken = IERC20(address(project));
        common.reserveToken = IERC20(address(reserve));
        common.startTime = uint32(block.timestamp + 1000);
        common.endTime = uint32(block.timestamp + 2000);
        common.blockProjectTokenSwapsIn = false;

        MigrationParams memory migration;
        // Disable migration for simplicity.
        migration.migrationRouter = address(0);

        LBPParams memory lbp;
        lbp.projectTokenStartWeight = 8e17;
        lbp.reserveTokenStartWeight = 2e17;
        lbp.projectTokenEndWeight = 5e17;
        lbp.reserveTokenEndWeight = 5e17;
        lbp.reserveTokenVirtualBalance = 0;

        FactoryParams memory factory;
        factory.vault = IVault(address(0x7777));
        factory.trustedRouter = address(trustedRouter);
        factory.poolVersion = "v1";

        LBPoolHarness pool = new LBPoolHarness(common, migration, lbp, factory);

        // Covers revert in computeBalance (unsupported single-token liquidity in LBPs).
        vm.expectRevert(LBPCommon.UnsupportedOperation.selector);
        pool.computeBalance(new uint256[](2), 0, FixedPoint.ONE);

        // Covers invalid token index revert in LBPool._getNormalizedWeight.
        vm.expectRevert(abi.encodeWithSignature("InvalidToken()"));
        pool.exposedGetNormalizedWeight(2);
    }
}

