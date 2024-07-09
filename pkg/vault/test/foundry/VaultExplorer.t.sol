// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { SwapKind, SwapParams } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import {
    TokenConfig,
    TokenInfo,
    TokenType,
    PoolRoleAccounts,
    LiquidityManagement,
    PoolData
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { PoolConfigLib, PoolConfigBits } from "../../contracts/lib/PoolConfigLib.sol";
import { VaultExplorer } from "../../contracts/VaultExplorer.sol";
import { PoolMock } from "../../contracts/test/PoolMock.sol";
import { RateProviderMock } from "../../contracts/test/RateProviderMock.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract VaultExplorerTest is BaseVaultTest {
    using PoolConfigLib for PoolConfigBits;
    using ScalingHelpers for uint256;
    using FixedPoint for uint256;
    using ArrayHelpers for *;
    using SafeCast for *;

    uint256 internal constant daiMockRate = 1.85e18;
    uint256 internal constant usdcMockRate = 7.243e17;

    uint256 internal constant daiRawBalance = 1000;
    uint256 internal constant usdcRawBalance = 2000;

    VaultExplorer internal explorer;

    // Track the indices for the standard dai/usdc pool.
    uint256 internal daiIdx;
    uint256 internal usdcIdx;

    RateProviderMock internal rateProviderDai;
    RateProviderMock internal rateProviderUsdc;
    uint8[] internal tokenDecimalDiffs;

    IRateProvider[] internal rateProviders;

    function setUp() public virtual override {
        BaseVaultTest.setUp();

        (daiIdx, usdcIdx) = getSortedIndexes(address(dai), address(usdc));

        rateProviderDai = new RateProviderMock();
        rateProviderDai.mockRate(daiMockRate);

        rateProviderUsdc = new RateProviderMock();
        rateProviderUsdc.mockRate(usdcMockRate);

        rateProviders = new IRateProvider[](2);
        rateProviders[daiIdx] = rateProviderDai;
        rateProviders[usdcIdx] = rateProviderUsdc;

        tokenDecimalDiffs = new uint8[](2);
        tokenDecimalDiffs[0] = 8;
        tokenDecimalDiffs[1] = 6;

        explorer = new VaultExplorer(vault);
    }

    function testGetVaultContracts() public view {
        assertEq(explorer.getVault(), address(vault), "Vault address mismatch");
        assertEq(explorer.getVaultExtension(), vault.getVaultExtension(), "Vault Extension address mismatch");
        assertEq(explorer.getVaultAdmin(), vault.getVaultAdmin(), "Vault Admin address mismatch");
        assertEq(explorer.getAuthorizer(), address(vault.getAuthorizer()), "Authorizer address mismatch");
        assertEq(
            explorer.getProtocolFeeController(),
            address(vault.getProtocolFeeController()),
            "Protocol Fee Controller address mismatch"
        );
    }

    function testPoolTokenCount() public view {
        (uint256 tokenCountVault, uint256 tokenIndexVault) = vault.getPoolTokenCountAndIndexOfToken(pool, dai);
        (uint256 tokenCountExplorer, uint256 tokenIndexExplorer) = explorer.getPoolTokenCountAndIndexOfToken(pool, dai);

        assertEq(tokenCountExplorer, tokenCountVault, "Token count mismatch");
        assertEq(tokenIndexExplorer, tokenIndexVault, "Token index mismatch");
    }

    function testUnlocked() public {
        assertFalse(explorer.isUnlocked(), "Should be locked");

        vault.manualSetIsUnlocked(true);
        assertTrue(explorer.isUnlocked(), "Should be unlocked");
    }

    function testNonzeroDeltaCount() public {
        assertEq(explorer.getNonzeroDeltaCount(), 0, "Wrong initial non-zero delta count");

        vault.manualSetNonZeroDeltaCount(47);
        assertEq(explorer.getNonzeroDeltaCount(), 47, "Wrong non-zero delta count");
    }

    function testGetTokenDelta() public {
        assertEq(vault.getTokenDelta(dai), 0, "Initial token delta non-zero (Vault)");
        assertEq(explorer.getTokenDelta(dai), 0, "Initial token delta non-zero (Explorer)");

        dai.mint(address(vault), defaultAmount);

        vault.manualSetIsUnlocked(true);
        uint256 settlementAmount = vault.settle(dai, defaultAmount);
        int256 vaultDelta = vault.getTokenDelta(dai);

        assertEq(settlementAmount, defaultAmount, "Wrong settlement amount");
        assertEq(vaultDelta, -settlementAmount.toInt256(), "Wrong Vault token delta");
        assertEq(explorer.getTokenDelta(dai), vaultDelta, "getTokenDelta mismatch");
    }

    function testGetReservesOf() public {
        dai.mint(address(vault), defaultAmount);

        assertEq(vault.getReservesOf(dai), defaultAmount, "Wrong Vault reserves");
        assertEq(explorer.getReservesOf(dai), defaultAmount, "Wrong Explorer reserves");
    }

    function testPoolRegistration() public {
        assertTrue(vault.isPoolRegistered(pool), "Default pool not registered (Vault)");
        assertTrue(explorer.isPoolRegistered(pool), "Default pool not registered (Explorer)");

        address newPool = address(new PoolMock(IVault(address(vault)), "ERC20 Pool", "ERC20POOL"));

        assertFalse(vault.isPoolRegistered(newPool), "New pool magically registered (Vault)");
        assertFalse(explorer.isPoolRegistered(newPool), "New pool magically registered (Explorer)");

        _registerPool(newPool, false);

        assertTrue(vault.isPoolRegistered(newPool), "New pool not registered (Vault)");
        assertTrue(explorer.isPoolRegistered(newPool), "New pool not registered (Explorer)");
    }

    function testPoolInitialization() public {
        assertTrue(vault.isPoolInitialized(pool), "Default pool not initialized (Vault)");
        assertTrue(explorer.isPoolInitialized(pool), "Default pool not initialized (Explorer)");

        address newPool = address(new PoolMock(IVault(address(vault)), "ERC20 Pool", "ERC20POOL"));

        _registerPool(newPool, true);

        assertTrue(vault.isPoolInitialized(newPool), "Default pool not initialized (Vault)");
        assertTrue(explorer.isPoolInitialized(newPool), "Default pool not initialized (Explorer)");
    }

    function testGetPoolTokens() public view {
        IERC20[] memory tokens = vault.getPoolTokens(pool);

        assertEq(address(tokens[daiIdx]), address(dai), "DAI token mismatch (Vault)");
        assertEq(address(tokens[usdcIdx]), address(usdc), "USDC token mismatch (Vault)");

        tokens = explorer.getPoolTokens(pool);

        assertEq(address(tokens[daiIdx]), address(dai), "DAI token mismatch (Explorer)");
        assertEq(address(tokens[usdcIdx]), address(usdc), "USDC token mismatch (Explorer)");
    }

    function testGetPoolTokenCountAndIndexOfToken() public view {
        (uint256 tokenCount, uint256 daiTokenIndex) = vault.getPoolTokenCountAndIndexOfToken(pool, dai);
        (, uint256 usdcTokenIndex) = vault.getPoolTokenCountAndIndexOfToken(pool, usdc);

        assertEq(tokenCount, 2, "Wrong token count (Vault)");
        assertEq(daiTokenIndex, daiIdx, "Wrong DAI token index (Vault)");
        assertEq(usdcTokenIndex, usdcIdx, "Wrong USDC token index (Vault)");

        (tokenCount, daiTokenIndex) = explorer.getPoolTokenCountAndIndexOfToken(pool, dai);
        (, usdcTokenIndex) = explorer.getPoolTokenCountAndIndexOfToken(pool, usdc);

        assertEq(tokenCount, 2, "Wrong token count (Explorer)");
        assertEq(daiTokenIndex, daiIdx, "Wrong DAI token index (Explorer)");
        assertEq(usdcTokenIndex, usdcIdx, "Wrong USDC token index (Explorer)");
    }

    function testGetPoolTokenRates() public {
        _setComplexPoolData();

        (uint256[] memory decimalScalingFactors, uint256[] memory tokenRates) = explorer.getPoolTokenRates(pool);

        assertEq(
            decimalScalingFactors.length,
            2,
            "length of decimalScalingFactors should be equal to amount of tokens"
        );

        assertEq(rateProviders[daiIdx].getRate(), daiMockRate, "DAI rate is wrong");
        assertEq(rateProviders[usdcIdx].getRate(), usdcMockRate, "USDC rate is wrong");

        for (uint256 i = 0; i < decimalScalingFactors.length; ++i) {
            assertEq(
                decimalScalingFactors[i],
                10 ** (18 + tokenDecimalDiffs[i]),
                string.concat("decimalScalingFactors of token", Strings.toString(i), "should match tokenDecimalDiffs")
            );

            assertEq(
                tokenRates[i],
                rateProviders[i].getRate(),
                string.concat("tokenRate of token", Strings.toString(i), "does not match mock providers.")
            );
        }
    }

    function testGetPoolData() public {
        _setComplexPoolData();

        PoolData memory poolData = explorer.getPoolData(pool);
        IERC20[] memory tokens = vault.getPoolTokens(pool);

        assertTrue(poolData.tokenInfo[daiIdx].paysYieldFees, "DAI doesn't pay yield fees");
        assertFalse(poolData.tokenInfo[usdcIdx].paysYieldFees, "USDC pays yield fees");

        assertTrue(poolData.poolConfigBits.isPoolRegistered(), "Pool not registered");
        assertTrue(poolData.poolConfigBits.isPoolInitialized(), "Pool not registered");

        assertEq(poolData.balancesRaw[daiIdx], daiRawBalance, "DAI raw balance wrong");
        assertEq(poolData.balancesRaw[usdcIdx], usdcRawBalance, "USDC raw balance wrong");

        uint256 daiLiveBalance = poolData.balancesRaw[daiIdx].toScaled18ApplyRateRoundDown(
            poolData.decimalScalingFactors[daiIdx],
            poolData.tokenRates[daiIdx]
        );
        uint256 usdcLiveBalance = poolData.balancesRaw[usdcIdx].toScaled18ApplyRateRoundDown(
            poolData.decimalScalingFactors[usdcIdx],
            poolData.tokenRates[usdcIdx]
        );

        assertEq(poolData.balancesLiveScaled18[daiIdx], daiLiveBalance, "DAI live balance wrong");
        assertEq(poolData.balancesLiveScaled18[usdcIdx], usdcLiveBalance, "USDC live balance wrong");

        for (uint256 i = 0; i < tokens.length; ++i) {
            assertEq(
                poolData.decimalScalingFactors[i],
                10 ** (18 + tokenDecimalDiffs[i]),
                string.concat("decimalScalingFactors of token ", Strings.toString(i), " should match tokenDecimalDiffs")
            );

            assertEq(
                poolData.tokenRates[i],
                rateProviders[i].getRate(),
                string.concat("tokenRate of token ", Strings.toString(i), " does not match mock providers.")
            );

            assertEq(
                address(poolData.tokens[i]),
                address(tokens[i]),
                string.concat("Address of token ", Strings.toString(i), " does not match.")
            );

            assertEq(
                uint8(poolData.tokenInfo[i].tokenType),
                uint8(TokenType.WITH_RATE),
                string.concat("Token type of token ", Strings.toString(i), " does not match")
            );
        }
    }

    function testGetPoolTokenInfo() public {
        _setComplexPoolData();

        (
            IERC20[] memory tokens,
            TokenInfo[] memory tokenInfo,
            uint256[] memory balancesRaw,
            uint256[] memory lastLiveBalances
        ) = explorer.getPoolTokenInfo(pool);

        assertTrue(tokenInfo[daiIdx].paysYieldFees, "DAI doesn't pay yield fees");
        assertFalse(tokenInfo[usdcIdx].paysYieldFees, "USDC pays yield fees");

        assertEq(address(tokenInfo[daiIdx].rateProvider), address(rateProviders[daiIdx]), "DAI rate provider mismatch");
        assertEq(address(tokenInfo[usdcIdx].rateProvider), address(rateProviders[usdcIdx]), "USDC rate provider mismatch");

        assertEq(balancesRaw[daiIdx], daiRawBalance, "DAI raw balance wrong");
        assertEq(balancesRaw[usdcIdx], usdcRawBalance, "USDC raw balance wrong");

        assertEq(lastLiveBalances[daiIdx], daiRawBalance, "DAI last live balance wrong");
        assertEq(lastLiveBalances[usdcIdx], usdcRawBalance, "USDC last live balance wrong");

        IERC20[] memory vaultTokens = vault.getPoolTokens(pool);

        for (uint256 i = 0; i < tokens.length; ++i) {
            assertEq(
                address(tokens[i]),
                address(vaultTokens[i]),
                string.concat("Address of token ", Strings.toString(i), " does not match.")
            );

            assertEq(
                uint8(tokenInfo[i].tokenType),
                uint8(TokenType.WITH_RATE),
                string.concat("Token type of token ", Strings.toString(i), " does not match")
            );
        }
    }

    function _registerPool(address newPool, bool initializeNewPool) private {
        IERC20[] memory tokens = InputHelpers.sortTokens([address(dai), address(usdc)].toMemoryArray().asIERC20());

        PoolRoleAccounts memory roleAccounts;
        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(tokens);
        LiquidityManagement memory liquidityManagement;

        explorer.registerPool(newPool, tokenConfig, 0, 0, false, roleAccounts, address(0), liquidityManagement);

        if (initializeNewPool) {
            vm.prank(alice);
            router.initialize(newPool, tokens, [defaultAmount, defaultAmount].toMemoryArray(), 0, false, bytes(""));
        }
    }

    function _setComplexPoolData() private {
        // Need different values of decimal scaling; taken from `testNonEmptyPoolConfig` in VaultCommonBasicFunctions.t.sol.
        IERC20[] memory tokens = InputHelpers.sortTokens([address(usdc), address(dai)].toMemoryArray().asIERC20());
        bool[] memory yieldFeeFlags = new bool[](2);
        yieldFeeFlags[daiIdx] = true;

        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(tokens, rateProviders, yieldFeeFlags);
        vault.manualSetPoolTokenInfo(pool, tokenConfig);

        // decimalScalingFactors depends on balances array (it's used gto calculate number of tokens)
        uint256[] memory rawBalances = new uint256[](2);
        rawBalances[daiIdx] = daiRawBalance;
        rawBalances[usdcIdx] = usdcRawBalance;

        vault.manualSetPoolTokensAndBalances(pool, tokens, rawBalances, rawBalances);

        PoolConfigBits originalPoolConfig;
        originalPoolConfig = originalPoolConfig
            .setTokenDecimalDiffs(PoolConfigLib.toTokenDecimalDiffs(tokenDecimalDiffs))
            .setPoolRegistered(true)
            .setPoolInitialized(true);

        vault.manualSetPoolConfigBits(pool, originalPoolConfig);
    }
}
