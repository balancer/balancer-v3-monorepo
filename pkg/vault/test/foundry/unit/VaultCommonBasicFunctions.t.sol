// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { PoolConfigLib } from "../../../contracts/lib/PoolConfigLib.sol";

import { BaseVaultTest } from "../utils/BaseVaultTest.sol";

contract VaultCommonBasicFunctionsTest is BaseVaultTest {
    using PoolConfigLib for PoolConfig;
    using SafeCast for *;

    // The balance and live balance are stored in the same bytes32 word, each uses 128 bits
    uint256 private constant _MAX_RAW_BALANCE = 2 ** 128 - 1;

    function setUp() public virtual override {
        BaseVaultTest.setUp();
    }

    function createPool() internal override returns (address) {
        // Generates a "random" address for a non-existent pool
        return address(bytes20(keccak256(abi.encode(block.timestamp))));
    }

    function initPool() internal override {}

    /*******************************************************************************
                                  _getPoolTokenInfo
    *******************************************************************************/

    function testEmptyPoolTokenConfig() public {
        (TokenConfig[] memory newTokenConfig, , , ) = vault.internalGetPoolTokenInfo(pool);
        assertEq(newTokenConfig.length, 0, "newTokenConfig should be empty");
    }

    function testNonEmptyPoolTokenBalance() public {
        IERC20[] memory tokens = new IERC20[](3);
        tokens[0] = usdc;
        tokens[1] = dai;
        tokens[2] = wsteth;
        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(tokens);
        vault.manualSetPoolTokenConfig(pool, tokens, tokenConfig);
        uint256[] memory originalBalancesRaw = new uint256[](3);
        originalBalancesRaw[0] = 1000;
        originalBalancesRaw[1] = 2000;
        originalBalancesRaw[2] = 3000;
        vault.manualSetPoolTokenBalances(pool, tokens, originalBalancesRaw);

        (TokenConfig[] memory newTokenConfig, uint256[] memory balancesRaw, , ) = vault.internalGetPoolTokenInfo(pool);
        assertEq(newTokenConfig.length, 3);
        assertEq(balancesRaw.length, 3);
        for (uint256 i = 0; i < newTokenConfig.length; i++) {
            assertEq(
                address(newTokenConfig[i].token),
                address(tokens[i]),
                string.concat("token", Strings.toString(i), "address is not correct")
            );
            assertEq(
                uint256(newTokenConfig[i].tokenType),
                uint256(TokenType.STANDARD),
                string.concat("token", Strings.toString(i), "should be STANDARD type")
            );
            assertEq(
                address(newTokenConfig[i].rateProvider),
                address(0),
                string.concat("token", Strings.toString(i), "should have no rate provider")
            );
            assertEq(
                newTokenConfig[i].yieldFeeExempt,
                false,
                string.concat("token", Strings.toString(i), "yieldFeeExempt flag should be false")
            );

            assertEq(
                balancesRaw[i],
                originalBalancesRaw[i],
                string.concat("token", Strings.toString(i), "balance should match set pool balance")
            );
        }
    }

    function testEmptyPoolConfig() public {
        PoolConfig memory emptyPoolConfig;

        (, , uint256[] memory decimalScalingFactors, PoolConfig memory poolConfig) = vault.internalGetPoolTokenInfo(
            pool
        );
        assertEq(decimalScalingFactors.length, 0, "should have no decimalScalingFactors");
        assertEq(
            bytes32(sha256(abi.encodePacked(poolConfig.fromPoolConfig()))),
            bytes32(sha256(abi.encodePacked(emptyPoolConfig.fromPoolConfig()))),
            "poolConfig should match empty pool config"
        );
    }

    function testNonEmptyPoolConfig() public {
        IERC20[] memory tokens = new IERC20[](3);
        tokens[0] = usdc;
        tokens[1] = dai;
        tokens[2] = wsteth;
        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(tokens);
        vault.manualSetPoolTokenConfig(pool, tokens, tokenConfig);

        // decimalScalingFactors depends on balances array (it's used gto calculate number of tokens)
        uint256[] memory rawBalances = new uint256[](3);
        rawBalances[0] = 1000;
        rawBalances[1] = 2000;
        rawBalances[2] = 3000;
        vault.manualSetPoolTokenBalances(pool, tokens, rawBalances);

        PoolConfig memory originalPoolConfig;
        uint8[] memory tokenDecimalDiffs = new uint8[](3);
        tokenDecimalDiffs[0] = 12;
        tokenDecimalDiffs[1] = 10;
        tokenDecimalDiffs[2] = 0;
        originalPoolConfig.tokenDecimalDiffs = PoolConfigLib.toTokenDecimalDiffs(tokenDecimalDiffs);
        vault.manualSetPoolConfig(pool, originalPoolConfig);

        (, , uint256[] memory decimalScalingFactors, PoolConfig memory newPoolConfig) = vault.internalGetPoolTokenInfo(
            pool
        );
        assertEq(
            decimalScalingFactors.length,
            3,
            "length of decimalScalingFactors should be equal to amount of tokens"
        );
        for (uint256 i = 0; i < decimalScalingFactors.length; i++) {
            assertEq(
                decimalScalingFactors[i],
                10 ** (18 + tokenDecimalDiffs[i]),
                string.concat("decimalScalingFactors of token", Strings.toString(i), "should match tokenDecimalDiffs")
            );
        }
        assertEq(
            bytes32(sha256(abi.encodePacked(newPoolConfig.fromPoolConfig()))),
            bytes32(sha256(abi.encodePacked(originalPoolConfig.fromPoolConfig()))),
            "original and new poolConfigs should be the same"
        );
    }

    function testInternalGetPoolTokenInfo__Fuzz(
        uint256 balance1,
        uint256 balance2,
        uint256 balance3,
        uint8 decimalDiff1,
        uint8 decimalDiff2,
        uint8 decimalDiff3
    ) public {
        balance1 = bound(balance1, 0, _MAX_RAW_BALANCE);
        balance2 = bound(balance2, 0, _MAX_RAW_BALANCE);
        balance3 = bound(balance3, 0, _MAX_RAW_BALANCE);
        decimalDiff1 = bound(decimalDiff1, 0, 18).toUint8();
        decimalDiff2 = bound(decimalDiff2, 0, 18).toUint8();
        decimalDiff3 = bound(decimalDiff3, 0, 18).toUint8();

        IERC20[] memory tokens = new IERC20[](3);
        tokens[0] = usdc;
        tokens[1] = dai;
        tokens[2] = wsteth;
        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(tokens);
        vault.manualSetPoolTokenConfig(pool, tokens, tokenConfig);

        // decimalScalingFactors depends on balances array (it's used gto calculate number of tokens)
        uint256[] memory originalBalancesRaw = new uint256[](3);
        originalBalancesRaw[0] = balance1;
        originalBalancesRaw[1] = balance2;
        originalBalancesRaw[2] = balance3;
        vault.manualSetPoolTokenBalances(pool, tokens, originalBalancesRaw);

        PoolConfig memory originalPoolConfig;
        uint8[] memory tokenDecimalDiffs = new uint8[](3);
        tokenDecimalDiffs[0] = decimalDiff1;
        tokenDecimalDiffs[1] = decimalDiff2;
        tokenDecimalDiffs[2] = decimalDiff3;
        originalPoolConfig.tokenDecimalDiffs = PoolConfigLib.toTokenDecimalDiffs(tokenDecimalDiffs);
        vault.manualSetPoolConfig(pool, originalPoolConfig);

        (
            TokenConfig[] memory newTokenConfig,
            uint256[] memory balancesRaw,
            uint256[] memory decimalScalingFactors,
            PoolConfig memory newPoolConfig
        ) = vault.internalGetPoolTokenInfo(pool);

        assertEq(newTokenConfig.length, 3);
        assertEq(balancesRaw.length, 3);
        assertEq(decimalScalingFactors.length, 3);

        for (uint256 i = 0; i < newTokenConfig.length; i++) {
            assertEq(
                address(newTokenConfig[i].token),
                address(tokens[i]),
                string.concat("token", Strings.toString(i), "address is not correct")
            );
            assertEq(
                uint256(newTokenConfig[i].tokenType),
                uint256(TokenType.STANDARD),
                string.concat("token", Strings.toString(i), "should be STANDARD type")
            );
            assertEq(
                address(newTokenConfig[i].rateProvider),
                address(0),
                string.concat("token", Strings.toString(i), "should have no rate provider")
            );
            assertEq(
                newTokenConfig[i].yieldFeeExempt,
                false,
                string.concat("token", Strings.toString(i), "yieldFeeExempt flag should be false")
            );

            assertEq(
                balancesRaw[i],
                originalBalancesRaw[i],
                string.concat("token", Strings.toString(i), "balance should match set pool balance")
            );
            assertEq(
                decimalScalingFactors[i],
                10 ** (18 + tokenDecimalDiffs[i]),
                string.concat("decimalScalingFactors of token", Strings.toString(i), "should match tokenDecimalDiffs")
            );
        }

        assertEq(
            bytes32(sha256(abi.encodePacked(newPoolConfig.fromPoolConfig()))),
            bytes32(sha256(abi.encodePacked(originalPoolConfig.fromPoolConfig()))),
            "original and new poolConfigs should be the same"
        );
    }

    function testAccountDeltaZero() public {
        vm.prank(alice);
        // Does not revert even with wrong locker.
        vault.accountDelta(dai, 0, bob);
    }

    function testAccountDeltaWrongLocker() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.WrongLocker.selector, bob, alice));
        vault.accountDelta(dai, 1, bob);
    }

    function testTakeDebtZero() public {
        vm.prank(alice);
        // Does not revert even with wrong locker.
        vault.takeDebt(dai, 0, bob);
    }

    function testTakeDebtWrongLocker() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.WrongLocker.selector, bob, alice));
        vault.takeDebt(dai, 1, bob);
    }

    function testSupplyCreditZero() public {
        vm.prank(alice);
        // Does not revert even with wrong locker.
        vault.supplyCredit(dai, 0, bob);
    }

    function testSupplyCreditWrongLocker() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.WrongLocker.selector, bob, alice));
        vault.supplyCredit(dai, 1, bob);
    }

    function testAccountDeltaNonZeroUp__Fuzz(int256 delta) public {
        vm.assume(delta != 0);
        int256 startingTokenDelta = vault.getTokenDelta(alice, dai);
        uint256 startingNonzeroDeltaCount = vault.getNonzeroDeltaCount();

        vm.prank(alice);
        vault.accountDelta(dai, delta, alice);

        assertEq(vault.getTokenDelta(alice, dai), startingTokenDelta + delta, "Incorrect token delta (token)");
        assertEq(vault.getNonzeroDeltaCount(), startingNonzeroDeltaCount + 1, "Incorrect non-zero delta count");
    }

    function testSupplyCreditNonZeroUp__Fuzz(uint256 delta) public {
        delta = bound(delta, 1, MAX_UINT128);
        int256 startingTokenDelta = vault.getTokenDelta(alice, dai);
        uint256 startingNonzeroDeltaCount = vault.getNonzeroDeltaCount();

        vm.prank(alice);
        vault.supplyCredit(dai, delta, alice);

        assertEq(
            vault.getTokenDelta(alice, dai),
            startingTokenDelta - delta.toInt256(),
            "Incorrect token delta (token)"
        );
        assertEq(vault.getNonzeroDeltaCount(), startingNonzeroDeltaCount + 1, "Incorrect non-zero delta count");
    }

    function testTakeDebtNonZeroUp__Fuzz(uint256 delta) public {
        delta = bound(delta, 1, MAX_UINT128);
        int256 startingTokenDelta = vault.getTokenDelta(alice, dai);
        uint256 startingNonzeroDeltaCount = vault.getNonzeroDeltaCount();

        vm.prank(alice);
        vault.takeDebt(dai, delta, alice);

        assertEq(
            vault.getTokenDelta(alice, dai),
            startingTokenDelta + delta.toInt256(),
            "Incorrect token delta (token)"
        );
        assertEq(vault.getNonzeroDeltaCount(), startingNonzeroDeltaCount + 1, "Incorrect non-zero delta count");
    }

    function testAccountDeltaNonZeroDown__Fuzz(int256 delta, uint256 startingNonZeroDeltaCount) public {
        delta = bound(delta, -MAX_UINT128.toInt256(), MAX_UINT128.toInt256());
        startingNonZeroDeltaCount = bound(startingNonZeroDeltaCount, 1, 10000);
        vm.assume(delta != 0);

        vault.manualSetAccountDelta(dai, alice, delta);
        vault.manualSetNonZeroDeltaCount(startingNonZeroDeltaCount);

        require(vault.getNonzeroDeltaCount() == startingNonZeroDeltaCount, "Starting non-zero delta count incorrect");
        require(vault.getTokenDelta(alice, dai) == delta, "Starting token delta incorrect");

        vm.prank(alice);
        vault.accountDelta(dai, -delta, alice);

        assertEq(vault.getTokenDelta(alice, dai), 0, "Incorrect token delta (token)");
        assertEq(vault.getNonzeroDeltaCount(), startingNonZeroDeltaCount - 1, "Incorrect non-zero delta count");
    }

    function testSupplyCreditNonZeroDown__Fuzz(int256 delta, uint256 startingNonZeroDeltaCount) public {
        delta = bound(delta, int256(1), MAX_UINT128.toInt256());
        startingNonZeroDeltaCount = bound(startingNonZeroDeltaCount, 1, 10000);

        vault.manualSetAccountDelta(dai, alice, delta);
        vault.manualSetNonZeroDeltaCount(startingNonZeroDeltaCount);

        require(vault.getNonzeroDeltaCount() == startingNonZeroDeltaCount, "Starting non-zero delta count incorrect");
        require(vault.getTokenDelta(alice, dai) == delta, "Starting token delta incorrect");

        vm.prank(alice);
        vault.supplyCredit(dai, delta.toUint256(), alice);

        assertEq(vault.getTokenDelta(alice, dai), 0, "Incorrect token delta (token)");
        assertEq(vault.getNonzeroDeltaCount(), startingNonZeroDeltaCount - 1, "Incorrect non-zero delta count");
    }

    function testTakeDebtNonZeroDown__Fuzz(int256 delta, uint256 startingNonZeroDeltaCount) public {
        delta = bound(delta, int256(1), MAX_UINT128.toInt256());
        startingNonZeroDeltaCount = bound(startingNonZeroDeltaCount, 1, 10000);

        vault.manualSetAccountDelta(dai, alice, -delta);
        vault.manualSetNonZeroDeltaCount(startingNonZeroDeltaCount);

        require(vault.getNonzeroDeltaCount() == startingNonZeroDeltaCount, "Starting non-zero delta count incorrect");
        require(vault.getTokenDelta(alice, dai) == -delta, "Starting token delta incorrect");

        vm.prank(alice);
        vault.takeDebt(dai, delta.toUint256(), alice);

        assertEq(vault.getTokenDelta(alice, dai), 0, "Incorrect token delta (token)");
        assertEq(vault.getNonzeroDeltaCount(), startingNonZeroDeltaCount - 1, "Incorrect non-zero delta count");
    }
}
