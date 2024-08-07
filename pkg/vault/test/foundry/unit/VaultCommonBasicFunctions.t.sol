// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IVaultEvents } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultEvents.sol";
import { ISwapFeePercentageBounds } from "@balancer-labs/v3-interfaces/contracts/vault/ISwapFeePercentageBounds.sol";
import {
    TokenConfig,
    TokenInfo,
    TokenType,
    FEE_SCALING_FACTOR,
    MAX_FEE_PERCENTAGE
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { PoolConfigLib, PoolConfigBits } from "../../../contracts/lib/PoolConfigLib.sol";

import { BaseVaultTest } from "../utils/BaseVaultTest.sol";

contract VaultCommonBasicFunctionsTest is BaseVaultTest {
    using PoolConfigLib for PoolConfigBits;
    using CastingHelpers for address[];
    using ArrayHelpers for *;
    using SafeCast for *;

    // The balance and live balance are stored in the same bytes32 word, each uses 128 bits.
    uint256 private constant _MAX_RAW_BALANCE = 2 ** 128 - 1;
    uint256 private constant MAX_TEST_SWAP_FEE = 10e16; // 10%
    uint256 private constant MIN_TEST_SWAP_FEE = 1e10; // 0.0001%

    function setUp() public virtual override {
        BaseVaultTest.setUp();
        // Generates a "random" address for a non-existent pool.
        pool = address(bytes20(keccak256(abi.encode(block.timestamp))));

        // Allow manual pool registration.
        vm.mockCall(
            pool,
            abi.encodeWithSelector(ISwapFeePercentageBounds.getMinimumSwapFeePercentage.selector),
            abi.encode(0)
        );
        vm.mockCall(
            pool,
            abi.encodeWithSelector(ISwapFeePercentageBounds.getMaximumSwapFeePercentage.selector),
            abi.encode(FixedPoint.ONE) // 100%
        );
    }

    function createPool() internal pure override returns (address) {
        return address(0);
    }

    function initPool() internal pure override {}

    /*******************************************************************************
                                  _getPoolTokenInfo
    *******************************************************************************/

    function testNonEmptyPoolTokenBalance() public {
        IERC20[] memory tokens = InputHelpers.sortTokens(
            [address(usdc), address(dai), address(wsteth)].toMemoryArray().asIERC20()
        );
        vault.manualRegisterPool(pool, tokens);

        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(tokens);
        vault.manualSetPoolTokenInfo(pool, tokenConfig);
        uint256[] memory originalBalancesRaw = new uint256[](3);
        originalBalancesRaw[0] = 1000;
        originalBalancesRaw[1] = 2000;
        originalBalancesRaw[2] = 3000;

        uint256[] memory originalLastLiveBalances = new uint256[](3);
        originalLastLiveBalances[0] = 123;
        originalLastLiveBalances[1] = 456;
        originalLastLiveBalances[2] = 789;

        vault.manualSetPoolTokensAndBalances(pool, tokens, originalBalancesRaw, originalLastLiveBalances);

        (
            IERC20[] memory newTokens,
            TokenInfo[] memory newTokenInfo,
            uint256[] memory balancesRaw,
            uint256[] memory lastBalancesLiveScaled18
        ) = vault.getPoolTokenInfo(pool);
        assertEq(newTokens.length, 3);
        assertEq(newTokenInfo.length, 3);
        assertEq(balancesRaw.length, 3);
        assertEq(lastBalancesLiveScaled18.length, 3);
        for (uint256 i = 0; i < newTokens.length; ++i) {
            assertEq(
                address(newTokens[i]),
                address(tokens[i]),
                string.concat("token", Strings.toString(i), "address is not correct")
            );
            assertEq(
                uint256(newTokenInfo[i].tokenType),
                uint256(TokenType.STANDARD),
                string.concat("token", Strings.toString(i), "should be STANDARD type")
            );
            assertEq(
                address(newTokenInfo[i].rateProvider),
                address(0),
                string.concat("token", Strings.toString(i), "should have no rate provider")
            );
            assertEq(
                newTokenInfo[i].paysYieldFees,
                false,
                string.concat("token", Strings.toString(i), "paysYieldFees flag should be false")
            );

            assertEq(
                balancesRaw[i],
                originalBalancesRaw[i],
                string.concat("token", Strings.toString(i), "balanceRaw should match set pool balance")
            );

            assertEq(
                lastBalancesLiveScaled18[i],
                originalLastLiveBalances[i],
                string.concat("token", Strings.toString(i), "lastBalancesLiveScaled18 should match set pool balance")
            );
        }
    }

    function testNonEmptyPoolConfig() public {
        IERC20[] memory tokens = InputHelpers.sortTokens(
            [address(usdc), address(dai), address(wsteth)].toMemoryArray().asIERC20()
        );
        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(tokens);
        vault.manualSetPoolTokenInfo(pool, tokenConfig);

        // decimalScalingFactors depends on balances array (it's used gto calculate number of tokens)
        // We don't care about last live balances for the purpose of this test.
        uint256[] memory rawBalances = new uint256[](3);
        rawBalances[0] = 1000;
        rawBalances[1] = 2000;
        rawBalances[2] = 3000;
        vault.manualSetPoolTokensAndBalances(pool, tokens, rawBalances, rawBalances);

        PoolConfigBits originalPoolConfig;
        uint8[] memory tokenDecimalDiffs = new uint8[](3);
        tokenDecimalDiffs[0] = 12;
        tokenDecimalDiffs[1] = 10;
        tokenDecimalDiffs[2] = 0;
        originalPoolConfig = originalPoolConfig.setTokenDecimalDiffs(
            PoolConfigLib.toTokenDecimalDiffs(tokenDecimalDiffs)
        );
        originalPoolConfig = originalPoolConfig.setPoolRegistered(true);
        vault.manualSetPoolConfigBits(pool, originalPoolConfig);

        (uint256[] memory decimalScalingFactors, ) = vault.getPoolTokenRates(pool);

        assertEq(
            decimalScalingFactors.length,
            3,
            "length of decimalScalingFactors should be equal to amount of tokens"
        );
        for (uint256 i = 0; i < decimalScalingFactors.length; ++i) {
            assertEq(
                decimalScalingFactors[i],
                10 ** (18 + tokenDecimalDiffs[i]),
                string.concat("decimalScalingFactors of token", Strings.toString(i), "should match tokenDecimalDiffs")
            );
        }
        assertEq(
            PoolConfigBits.unwrap(vault.manualGetPoolConfigBits(pool)),
            PoolConfigBits.unwrap(originalPoolConfig),
            "original and new poolConfigs should be the same"
        );
    }

    function testGetPoolTokenInfo__Fuzz(
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

        IERC20[] memory tokens = InputHelpers.sortTokens(
            [address(usdc), address(dai), address(wsteth)].toMemoryArray().asIERC20()
        );
        vault.manualRegisterPool(pool, tokens);

        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(tokens);
        vault.manualSetPoolTokenInfo(pool, tokenConfig);

        // decimalScalingFactors depends on balances array (it's used gto calculate number of tokens).
        uint256[] memory originalBalancesRaw = new uint256[](3);
        originalBalancesRaw[0] = balance1;
        originalBalancesRaw[1] = balance2;
        originalBalancesRaw[2] = balance3;

        uint256[] memory originalLastLiveBalances = new uint256[](3);
        originalLastLiveBalances[0] = balance2;
        originalLastLiveBalances[1] = balance3;
        originalLastLiveBalances[2] = balance1;
        vault.manualSetPoolTokensAndBalances(pool, tokens, originalBalancesRaw, originalLastLiveBalances);

        (
            IERC20[] memory newTokens,
            TokenInfo[] memory newTokenInfo,
            uint256[] memory balancesRaw,
            uint256[] memory lastBalancesLiveScaled18
        ) = vault.getPoolTokenInfo(pool);

        assertEq(newTokens.length, 3);
        assertEq(newTokenInfo.length, 3);
        assertEq(balancesRaw.length, 3);
        assertEq(lastBalancesLiveScaled18.length, 3);

        for (uint256 i = 0; i < newTokens.length; ++i) {
            assertEq(
                address(newTokens[i]),
                address(tokens[i]),
                string.concat("token", Strings.toString(i), "address is not correct")
            );
            assertEq(
                uint256(newTokenInfo[i].tokenType),
                uint256(TokenType.STANDARD),
                string.concat("token", Strings.toString(i), "should be STANDARD type")
            );
            assertEq(
                address(newTokenInfo[i].rateProvider),
                address(0),
                string.concat("token", Strings.toString(i), "should have no rate provider")
            );
            assertEq(
                newTokenInfo[i].paysYieldFees,
                false,
                string.concat("token", Strings.toString(i), "paysYieldFees flag should be false")
            );

            assertEq(
                balancesRaw[i],
                originalBalancesRaw[i],
                string.concat("token", Strings.toString(i), "balance should match set pool balance")
            );
            assertEq(
                lastBalancesLiveScaled18[i],
                originalLastLiveBalances[i],
                string.concat("decimalScalingFactors of token", Strings.toString(i), "should match tokenDecimalDiffs")
            );
        }
    }

    function testAccountDeltaNonZeroUp__Fuzz(int256 delta) public {
        vm.assume(delta != 0);
        int256 startingTokenDelta = vault.getTokenDelta(dai);
        uint256 startingNonzeroDeltaCount = vault.getNonzeroDeltaCount();

        vm.prank(alice);
        vault.accountDelta(dai, delta);

        assertEq(vault.getTokenDelta(dai), startingTokenDelta + delta, "Incorrect token delta (token)");
        assertEq(vault.getNonzeroDeltaCount(), startingNonzeroDeltaCount + 1, "Incorrect non-zero delta count");
    }

    function testSupplyCreditNonZeroUp__Fuzz(uint256 delta) public {
        delta = bound(delta, 1, MAX_UINT128);
        int256 startingTokenDelta = vault.getTokenDelta(dai);
        uint256 startingNonzeroDeltaCount = vault.getNonzeroDeltaCount();

        vm.prank(alice);
        vault.supplyCredit(dai, delta);

        assertEq(vault.getTokenDelta(dai), startingTokenDelta - delta.toInt256(), "Incorrect token delta (token)");
        assertEq(vault.getNonzeroDeltaCount(), startingNonzeroDeltaCount + 1, "Incorrect non-zero delta count");
    }

    function testTakeDebtNonZeroUp__Fuzz(uint256 delta) public {
        delta = bound(delta, 1, MAX_UINT128);
        int256 startingTokenDelta = vault.getTokenDelta(dai);
        uint256 startingNonzeroDeltaCount = vault.getNonzeroDeltaCount();

        vm.prank(alice);
        vault.takeDebt(dai, delta);

        assertEq(vault.getTokenDelta(dai), startingTokenDelta + delta.toInt256(), "Incorrect token delta (token)");
        assertEq(vault.getNonzeroDeltaCount(), startingNonzeroDeltaCount + 1, "Incorrect non-zero delta count");
    }

    function testAccountDeltaNonZeroDown__Fuzz(int256 delta, uint256 startingNonZeroDeltaCount) public {
        delta = bound(delta, -MAX_UINT128.toInt256(), MAX_UINT128.toInt256());
        startingNonZeroDeltaCount = bound(startingNonZeroDeltaCount, 1, 10000);
        vm.assume(delta != 0);

        vault.manualSetAccountDelta(dai, delta);
        vault.manualSetNonZeroDeltaCount(startingNonZeroDeltaCount);

        require(vault.getNonzeroDeltaCount() == startingNonZeroDeltaCount, "Starting non-zero delta count incorrect");
        require(vault.getTokenDelta(dai) == delta, "Starting token delta incorrect");

        vm.prank(alice);
        vault.accountDelta(dai, -delta);

        assertEq(vault.getTokenDelta(dai), 0, "Incorrect token delta (token)");
        assertEq(vault.getNonzeroDeltaCount(), startingNonZeroDeltaCount - 1, "Incorrect non-zero delta count");
    }

    function testSupplyCreditNonZeroDown__Fuzz(int256 delta, uint256 startingNonZeroDeltaCount) public {
        delta = bound(delta, int256(1), MAX_UINT128.toInt256());
        startingNonZeroDeltaCount = bound(startingNonZeroDeltaCount, 1, 10000);

        vault.manualSetAccountDelta(dai, delta);
        vault.manualSetNonZeroDeltaCount(startingNonZeroDeltaCount);

        require(vault.getNonzeroDeltaCount() == startingNonZeroDeltaCount, "Starting non-zero delta count incorrect");
        require(vault.getTokenDelta(dai) == delta, "Starting token delta incorrect");

        vm.prank(alice);
        vault.supplyCredit(dai, delta.toUint256());

        assertEq(vault.getTokenDelta(dai), 0, "Incorrect token delta (token)");
        assertEq(vault.getNonzeroDeltaCount(), startingNonZeroDeltaCount - 1, "Incorrect non-zero delta count");
    }

    function testTakeDebtNonZeroDown__Fuzz(int256 delta, uint256 startingNonZeroDeltaCount) public {
        delta = bound(delta, int256(1), MAX_UINT128.toInt256());
        startingNonZeroDeltaCount = bound(startingNonZeroDeltaCount, 1, 10000);

        vault.manualSetAccountDelta(dai, -delta);
        vault.manualSetNonZeroDeltaCount(startingNonZeroDeltaCount);

        require(vault.getNonzeroDeltaCount() == startingNonZeroDeltaCount, "Starting non-zero delta count incorrect");
        require(vault.getTokenDelta(dai) == -delta, "Starting token delta incorrect");

        vm.prank(alice);
        vault.takeDebt(dai, delta.toUint256());

        assertEq(vault.getTokenDelta(dai), 0, "Incorrect token delta (token)");
        assertEq(vault.getNonzeroDeltaCount(), startingNonZeroDeltaCount - 1, "Incorrect non-zero delta count");
    }

    function testSetStaticSwapFeePercentage__Fuzz(uint256 fee) public {
        vault.manualSetPoolRegistered(pool, true);
        fee = bound(fee, MIN_TEST_SWAP_FEE, MAX_TEST_SWAP_FEE);
        vm.mockCall(
            address(pool),
            abi.encodeWithSelector(ISwapFeePercentageBounds.getMinimumSwapFeePercentage.selector),
            abi.encode(MIN_TEST_SWAP_FEE)
        );
        vm.mockCall(
            address(pool),
            abi.encodeWithSelector(ISwapFeePercentageBounds.getMaximumSwapFeePercentage.selector),
            abi.encode(MAX_TEST_SWAP_FEE)
        );

        vm.expectEmit();
        emit IVaultEvents.SwapFeePercentageChanged(pool, fee);

        vault.manualSetStaticSwapFeePercentage(pool, fee);
        uint256 feeTruncated = (fee / FEE_SCALING_FACTOR) * FEE_SCALING_FACTOR;
        assertEq(vault.getStaticSwapFeePercentage(pool), feeTruncated, "Wrong static swap fee percentage");
    }

    function testSetStaticSwapFeePercentageOutsideBounds() public {
        vault.manualSetPoolRegistered(pool, true);
        vm.mockCall(
            address(pool),
            abi.encodeWithSelector(ISwapFeePercentageBounds.getMinimumSwapFeePercentage.selector),
            abi.encode(MIN_TEST_SWAP_FEE)
        );
        vm.mockCall(
            address(pool),
            abi.encodeWithSelector(ISwapFeePercentageBounds.getMaximumSwapFeePercentage.selector),
            abi.encode(MAX_TEST_SWAP_FEE)
        );

        vm.expectRevert(IVaultErrors.SwapFeePercentageTooLow.selector);
        vault.manualSetStaticSwapFeePercentage(pool, MIN_TEST_SWAP_FEE - 1);

        vm.expectRevert(IVaultErrors.SwapFeePercentageTooHigh.selector);
        vault.manualSetStaticSwapFeePercentage(pool, MAX_TEST_SWAP_FEE + 1);

        vm.mockCall(
            address(pool),
            abi.encodeWithSelector(ISwapFeePercentageBounds.getMaximumSwapFeePercentage.selector),
            abi.encode(MAX_FEE_PERCENTAGE + 10)
        );

        // Also revert if it's above the maximum limit.
        vm.expectRevert(abi.encodeWithSelector(PoolConfigLib.InvalidPercentage.selector, MAX_FEE_PERCENTAGE + 1));
        vault.manualSetStaticSwapFeePercentage(pool, MAX_FEE_PERCENTAGE + 1);
    }

    function testFindTokenIndex__Fuzz(address[8] memory tokensRaw, uint256 tokenIndex, uint256 length) public view {
        length = bound(length, 1, 8);
        tokenIndex = bound(tokenIndex, 0, length - 1);

        IERC20[] memory tokens = new IERC20[](length);
        IERC20 lastToken = IERC20(address(0));
        for (uint256 i = 0; i < length; ++i) {
            IERC20 currentToken = IERC20(tokensRaw[i]);
            vm.assume(currentToken > lastToken);
            tokens[i] = currentToken;
            lastToken = currentToken;
        }
        IERC20 token = IERC20(tokens[tokenIndex]);

        uint256 actualTokenIndex = vault.manualFindTokenIndex(tokens, token);
        assertEq(actualTokenIndex, tokenIndex, "Incorrect token index");
    }

    function testFindTokenIndexNotRegistered__Fuzz(address[8] memory tokensRaw, uint256 length) public {
        length = bound(length, 1, 8);
        IERC20 nonRegisteredToken = IERC20(0x0Ba1Ba1BA1ba1Ba1Ba1ba1BA1Ba1BA1Ba1ba1Ba1);

        IERC20[] memory tokens = new IERC20[](length);
        for (uint256 i = 0; i < length; ++i) {
            IERC20 currentToken = IERC20(tokensRaw[i]);
            vm.assume(currentToken != nonRegisteredToken);
            tokens[i] = currentToken;
        }

        vm.expectRevert(abi.encodeWithSelector(IVaultErrors.TokenNotRegistered.selector, nonRegisteredToken));
        vault.manualFindTokenIndex(tokens, nonRegisteredToken);
    }
}
