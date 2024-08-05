// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { IAuthentication } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IAuthentication.sol";
import { IProtocolFeeController } from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeeController.sol";
import { SwapKind, SwapParams } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import {
    TokenConfig,
    TokenInfo,
    TokenType,
    PoolRoleAccounts,
    LiquidityManagement,
    PoolConfig,
    HooksConfig,
    PoolData,
    PoolSwapParams
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { PoolHooksMock } from "@balancer-labs/v3-vault/contracts/test/PoolHooksMock.sol";
import { ERC4626TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC4626TestToken.sol";

import { PoolConfigLib, PoolConfigBits } from "../../contracts/lib/PoolConfigLib.sol";
import { VaultExplorer } from "../../contracts/VaultExplorer.sol";
import { PoolMock } from "../../contracts/test/PoolMock.sol";
import { RateProviderMock } from "../../contracts/test/RateProviderMock.sol";

import { BaseVaultTest } from "./utils/BaseVaultTest.sol";

contract VaultExplorerTest is BaseVaultTest {
    using PoolConfigLib for PoolConfigBits;
    using CastingHelpers for address[];
    using ScalingHelpers for uint256;
    using FixedPoint for uint256;
    using ArrayHelpers for *;
    using SafeCast for *;

    uint256 internal constant PROTOCOL_SWAP_FEE = 50e16;
    uint256 internal constant PROTOCOL_YIELD_FEE = 20e16;

    uint256 internal constant DAI_MOCK_RATE = 1.85e18;
    uint256 internal constant USDC_MOCK_RATE = 7.243e17;

    uint256 internal constant DAI_RAW_BALANCE = 1000;
    uint256 internal constant USDC_RAW_BALANCE = 2000;

    uint256 internal constant PROTOCOL_SWAP_FEE_AMOUNT = 100e18;
    uint256 internal constant PROTOCOL_YIELD_FEE_AMOUNT = 50e18;

    VaultExplorer internal explorer;
    IAuthentication feeControllerAuth;
    ERC4626TestToken internal waDAI;

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
        rateProviderDai.mockRate(DAI_MOCK_RATE);

        rateProviderUsdc = new RateProviderMock();
        rateProviderUsdc.mockRate(USDC_MOCK_RATE);

        rateProviders = new IRateProvider[](2);
        rateProviders[daiIdx] = rateProviderDai;
        rateProviders[usdcIdx] = rateProviderUsdc;

        tokenDecimalDiffs = new uint8[](2);
        tokenDecimalDiffs[0] = 8;
        tokenDecimalDiffs[1] = 6;

        _setComplexPoolData();

        feeControllerAuth = IAuthentication(address(feeController));

        waDAI = new ERC4626TestToken(dai, "Wrapped aDAI", "waDAI", 18);

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

        vault.manualSetIsUnlocked(true);
        uint256 settlementAmount = vault.settle(dai, defaultAmount);

        assertEq(settlementAmount, defaultAmount, "Wrong settlement amount");
        assertEq(vault.getReservesOf(dai), defaultAmount * 2, "Wrong Vault reserves");
        assertEq(explorer.getReservesOf(dai), defaultAmount * 2, "Wrong Explorer reserves");
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

    function testGetPoolTokenRates() public view {
        (uint256[] memory decimalScalingFactors, uint256[] memory tokenRates) = explorer.getPoolTokenRates(pool);

        assertEq(
            decimalScalingFactors.length,
            2,
            "length of decimalScalingFactors should be equal to amount of tokens"
        );

        assertEq(rateProviders[daiIdx].getRate(), DAI_MOCK_RATE, "DAI rate is wrong");
        assertEq(rateProviders[usdcIdx].getRate(), USDC_MOCK_RATE, "USDC rate is wrong");

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

    function testGetPoolData() public view {
        PoolData memory poolData = explorer.getPoolData(pool);
        IERC20[] memory tokens = vault.getPoolTokens(pool);

        assertTrue(poolData.tokenInfo[daiIdx].paysYieldFees, "DAI doesn't pay yield fees");
        assertFalse(poolData.tokenInfo[usdcIdx].paysYieldFees, "USDC pays yield fees");

        assertTrue(poolData.poolConfigBits.isPoolRegistered(), "Pool not registered");
        assertTrue(poolData.poolConfigBits.isPoolInitialized(), "Pool not registered");

        assertEq(poolData.balancesRaw[daiIdx], DAI_RAW_BALANCE, "DAI raw balance wrong");
        assertEq(poolData.balancesRaw[usdcIdx], USDC_RAW_BALANCE, "USDC raw balance wrong");

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

    function testGetPoolTokenInfo() public view {
        (
            IERC20[] memory tokens,
            TokenInfo[] memory tokenInfo,
            uint256[] memory balancesRaw,
            uint256[] memory lastLiveBalances
        ) = explorer.getPoolTokenInfo(pool);

        assertTrue(tokenInfo[daiIdx].paysYieldFees, "DAI doesn't pay yield fees");
        assertFalse(tokenInfo[usdcIdx].paysYieldFees, "USDC pays yield fees");

        assertEq(address(tokenInfo[daiIdx].rateProvider), address(rateProviders[daiIdx]), "DAI rate provider mismatch");
        assertEq(
            address(tokenInfo[usdcIdx].rateProvider),
            address(rateProviders[usdcIdx]),
            "USDC rate provider mismatch"
        );

        assertEq(balancesRaw[daiIdx], DAI_RAW_BALANCE, "DAI raw balance wrong");
        assertEq(balancesRaw[usdcIdx], USDC_RAW_BALANCE, "USDC raw balance wrong");

        assertEq(lastLiveBalances[daiIdx], DAI_RAW_BALANCE, "DAI last live balance wrong");
        assertEq(lastLiveBalances[usdcIdx], USDC_RAW_BALANCE, "USDC last live balance wrong");

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

    function testGetCurrentLiveBalances() public view {
        // Calculate live balances using the Vault (kind of overkill, as they're fetched directly below).
        PoolData memory poolData = vault.getPoolData(pool);

        uint256 daiLiveBalance = poolData.balancesRaw[daiIdx].toScaled18ApplyRateRoundDown(
            poolData.decimalScalingFactors[daiIdx],
            poolData.tokenRates[daiIdx]
        );
        uint256 usdcLiveBalance = poolData.balancesRaw[usdcIdx].toScaled18ApplyRateRoundDown(
            poolData.decimalScalingFactors[usdcIdx],
            poolData.tokenRates[usdcIdx]
        );

        uint256[] memory vaultBalancesLiveScaled18 = vault.getCurrentLiveBalances(pool);
        assertEq(vaultBalancesLiveScaled18.length, 2, "Invalid live balances array (Vault)");

        uint256[] memory balancesLiveScaled18 = explorer.getCurrentLiveBalances(pool);
        assertEq(balancesLiveScaled18.length, 2, "Invalid live balances array (Explorer)");

        assertEq(balancesLiveScaled18[daiIdx], daiLiveBalance, "DAI live balance wrong (calculated)");
        assertEq(balancesLiveScaled18[usdcIdx], usdcLiveBalance, "USDC live balance wrong (calculated)");

        assertEq(balancesLiveScaled18[daiIdx], vaultBalancesLiveScaled18[daiIdx], "DAI live balance wrong (Vault)");
        assertEq(balancesLiveScaled18[usdcIdx], vaultBalancesLiveScaled18[usdcIdx], "USDC live balance wrong (Vault)");
    }

    function testGetPoolConfig() public {
        PoolConfig memory poolConfig = explorer.getPoolConfig(pool);

        // Check the flags.
        assertTrue(poolConfig.isPoolRegistered, "Pool not registered");
        assertTrue(poolConfig.isPoolInitialized, "Pool not initialized");
        assertFalse(poolConfig.isPoolPaused, "Pool is paused");
        assertFalse(poolConfig.isPoolInRecoveryMode, "Pool is in recovery mode");

        // Change something.
        vault.manualSetPoolPauseWindowEndTime(pool, uint32(block.timestamp) + 365 days);
        vault.manualPausePool(pool);

        poolConfig = explorer.getPoolConfig(pool);
        assertTrue(poolConfig.isPoolPaused, "Pool is not paused");
    }

    function testGetHooksConfig() public {
        HooksConfig memory hooksConfig = explorer.getHooksConfig(pool);

        assertEq(hooksConfig.hooksContract, poolHooksContract, "Wrong hooks contract");
        assertFalse(hooksConfig.shouldCallComputeDynamicSwapFee, "Dynamic swap fee flag is true");

        // Change something.
        hooksConfig.shouldCallComputeDynamicSwapFee = true;
        vault.manualSetHooksConfig(pool, hooksConfig);

        hooksConfig = explorer.getHooksConfig(pool);
        assertTrue(hooksConfig.shouldCallComputeDynamicSwapFee, "Dynamic swap fee flag is false");
    }

    function testGetBptRate() public view {
        PoolData memory poolData = vault.getPoolData(pool);

        uint256 invariant = IBasePool(pool).computeInvariant(poolData.balancesLiveScaled18);
        uint256 expectedRate = invariant.divDown(vault.totalSupply(pool));

        uint256 bptRate = explorer.getBptRate(pool);

        assertEq(bptRate, expectedRate, "Wrong BPT rate");
    }

    function testTotalSupply() public view {
        uint256 vaultTotalSupply = vault.totalSupply(address(pool));

        assertTrue(vaultTotalSupply > 0, "Vault total supply is zero");

        assertEq(explorer.totalSupply(address(pool)), vaultTotalSupply, "Total supply mismatch");
    }

    function testBalanceOf() public view {
        uint256 bptBalance = vault.balanceOf(address(pool), lp);

        assertTrue(bptBalance > 0, "LP's BPT balance is zero");

        assertEq(explorer.balanceOf(address(pool), lp), bptBalance, "BPT balance mismatch");
    }

    function testAllowance() public view {
        uint256 daiVaultAllowance = vault.allowance(address(dai), lp, address(vault));
        uint256 daiBobAllowance = vault.allowance(address(dai), alice, bob);

        assertEq(daiVaultAllowance, MAX_UINT256, "Wrong DAI Vault allowance");
        assertEq(daiBobAllowance, 0, "Wrong DAI Bob allowance");

        assertEq(
            explorer.allowance(address(dai), lp, address(vault)),
            daiVaultAllowance,
            "DAI Vault allowance mismatch"
        );
        assertEq(explorer.allowance(address(dai), alice, bob), daiBobAllowance, "DAI Bob allowance mismatch");
    }

    function testIsPoolPaused() public {
        assertFalse(explorer.isPoolPaused(pool), "Pool is initially paused");

        vault.manualSetPoolPauseWindowEndTime(pool, uint32(block.timestamp) + 365 days);
        vault.manualPausePool(pool);

        assertTrue(explorer.isPoolPaused(pool), "Pool is not paused");
    }

    function testGetPoolPausedState() public {
        (bool paused, uint256 poolPauseWindowEndTime, uint256 poolBufferPeriodEndTime, address pauseManager) = explorer
            .getPoolPausedState(pool);

        assertFalse(paused, "Pool is initially paused");
        assertEq(poolPauseWindowEndTime, 0, "Non-zero initial end time");
        assertEq(poolBufferPeriodEndTime, vault.getBufferPeriodDuration(), "Wrong initial buffer time");
        assertEq(pauseManager, address(0), "Pool has a pause manager");

        // Change the state.
        uint32 newEndTime = uint32(block.timestamp) + 365 days;

        vault.manualSetPoolPauseWindowEndTime(pool, newEndTime);
        vault.manualPausePool(pool);

        (paused, poolPauseWindowEndTime, poolBufferPeriodEndTime, ) = explorer.getPoolPausedState(pool);

        assertTrue(paused, "Pool is not paused");
        assertEq(poolPauseWindowEndTime, newEndTime, "Non-zero initial end time");
        assertEq(poolBufferPeriodEndTime, newEndTime + vault.getBufferPeriodDuration(), "Wrong initial buffer time");
    }

    function testGetAggregateSwapFeeAmount() public {
        uint256 swapFees = explorer.getAggregateSwapFeeAmount(pool, dai);

        assertEq(swapFees, 0, "Non-zero initial swap fees");

        vault.manualSetAggregateSwapFeeAmount(pool, dai, defaultAmount);

        swapFees = explorer.getAggregateSwapFeeAmount(pool, dai);
        assertEq(swapFees, defaultAmount, "Swap fees are zero");
    }

    function testGetAggregateYieldFeeAmount() public {
        uint256 yieldFees = explorer.getAggregateYieldFeeAmount(pool, dai);

        assertEq(yieldFees, 0, "Non-zero initial yield fees");

        vault.manualSetAggregateYieldFeeAmount(pool, dai, defaultAmount);

        yieldFees = explorer.getAggregateYieldFeeAmount(pool, dai);
        assertEq(yieldFees, defaultAmount, "Yield fees are zero");
    }

    function testGetStaticSwapFeePercentage() public {
        uint256 explorerSwapFeePercentage = explorer.getStaticSwapFeePercentage(pool);

        assertEq(explorerSwapFeePercentage, 0, "Non-zero initial swap fee");

        assertTrue(swapFeePercentage > 0, "Swap fee is zero");
        vault.manualSetStaticSwapFeePercentage(pool, swapFeePercentage);

        explorerSwapFeePercentage = explorer.getStaticSwapFeePercentage(pool);
        assertEq(explorerSwapFeePercentage, swapFeePercentage, "Wrong swap fee");
    }

    function testGetPoolRoleAccounts() public view {
        PoolRoleAccounts memory vaultRoleAccounts = vault.getPoolRoleAccounts(pool);
        PoolRoleAccounts memory explorerRoleAccounts = explorer.getPoolRoleAccounts(pool);

        assertEq(vaultRoleAccounts.poolCreator, lp, "Pool creator is not LP");

        assertEq(vaultRoleAccounts.pauseManager, explorerRoleAccounts.pauseManager, "Pause manager mmismatch");
        assertEq(vaultRoleAccounts.swapFeeManager, explorerRoleAccounts.swapFeeManager, "Swap fee manager mmismatch");
        assertEq(vaultRoleAccounts.poolCreator, explorerRoleAccounts.poolCreator, "Pool creator mmismatch");
    }

    function testComputeDynamicSwapFeePercentage() public {
        assertTrue(swapFeePercentage > 0, "Swap fee is zero");
        PoolHooksMock(poolHooksContract).setDynamicSwapFeePercentage(swapFeePercentage);

        (bool success, uint256 dynamicSwapFeePercentage) = explorer.computeDynamicSwapFeePercentage(
            pool,
            PoolSwapParams({
                kind: SwapKind.EXACT_IN,
                amountGivenScaled18: defaultAmount,
                balancesScaled18: [defaultAmount, defaultAmount].toMemoryArray(),
                indexIn: daiIdx,
                indexOut: usdcIdx,
                router: address(0),
                userData: bytes("")
            })
        );

        assertTrue(success, "Vault dynamic fee call failed");
        // Should default to the static fee.
        assertEq(dynamicSwapFeePercentage, swapFeePercentage, "Wrong dynamic fee percentage");
    }

    function testIsPoolInRecoveryMode() public {
        assertFalse(explorer.isPoolInRecoveryMode(pool), "Pool is initially in recovery mode");

        vault.manualSetPoolPauseWindowEndTime(pool, uint32(block.timestamp) + 365 days);
        vault.manualPausePool(pool);

        vault.enableRecoveryMode(pool);

        assertTrue(explorer.isPoolPaused(pool), "Pool is not paused");
        assertTrue(explorer.isPoolInRecoveryMode(pool), "Pool is not in recovery mode");
    }

    function testIsQueryDisabled() public {
        assertFalse(explorer.isQueryDisabled(), "Queries are initially disabled");

        bytes32 disableQueryRole = vault.getActionId(IVaultAdmin.disableQuery.selector);
        authorizer.grantRole(disableQueryRole, alice);

        vm.prank(alice);
        vault.disableQuery();

        assertTrue(explorer.isQueryDisabled(), "Queries are not disabled");
    }

    function testGetPauseWindowEndTime() public view {
        uint256 vaultEndTime = vault.getPauseWindowEndTime();

        assertTrue(vaultEndTime > 0, "Zero pause window end time");
        assertEq(explorer.getPauseWindowEndTime(), vaultEndTime, "Pause window end time mismatch");
    }

    function testGetBufferPeriodDuration() public view {
        uint256 vaultBufferDuration = vault.getBufferPeriodDuration();

        assertTrue(vaultBufferDuration > 0, "Zero buffer period duration");
        assertEq(explorer.getBufferPeriodDuration(), vaultBufferDuration, "Buffer period duration mismatch");
    }

    function testGetBufferPeriodEndTime() public view {
        uint256 vaultBufferEndTime = vault.getBufferPeriodEndTime();

        assertTrue(vaultBufferEndTime > 0, "Zero buffer period end time");
        assertEq(explorer.getBufferPeriodEndTime(), vaultBufferEndTime, "Buffer period end time mismatch");
    }

    function testGetMinimumPoolTokens() public view {
        uint256 vaultMinimum = vault.getMinimumPoolTokens();

        assertEq(vaultMinimum, 2, "Unexpected minimum pool tokens");
        assertEq(explorer.getMinimumPoolTokens(), vaultMinimum, "Minimum pool token mismatch");
    }

    function testGetMaximumPoolTokens() public view {
        uint256 vaultMaximum = vault.getMaximumPoolTokens();

        assertEq(vaultMaximum, 8, "Unexpected maximum pool tokens");
        assertEq(explorer.getMaximumPoolTokens(), vaultMaximum, "Maximum pool token mismatch");
    }

    function testIsVaultPaused() public {
        assertFalse(vault.isVaultPaused(), "Vault is paused");
        assertFalse(explorer.isVaultPaused(), "Explorer says Vault is paused");

        vault.manualPauseVault();

        assertTrue(vault.isVaultPaused(), "Vault is not paused");
        assertTrue(explorer.isVaultPaused(), "Explorer says Vault is not paused");
    }

    function testGetVaultPausedState() public {
        (bool vaultIsPaused, uint32 vaultPauseWindowEndTime, uint32 vaultBufferPeriodEndTime) = vault
            .getVaultPausedState();

        assertFalse(vaultIsPaused, "Vault is paused");
        assertTrue(vaultPauseWindowEndTime > 0, "Zero pause window end time");
        assertTrue(vaultBufferPeriodEndTime > 0, "Zero buffer period end time");

        (bool explorerIsPaused, uint32 explorerPauseWindowEndTime, uint32 explorerBufferPeriodEndTime) = explorer
            .getVaultPausedState();

        assertFalse(explorerIsPaused, "Explorer says Vault is paused");
        assertEq(vaultPauseWindowEndTime, explorerPauseWindowEndTime, "Pause window end time mismatch");
        assertEq(vaultBufferPeriodEndTime, explorerBufferPeriodEndTime, "Buffer period end time mismatch");

        vault.manualPauseVault();

        (explorerIsPaused, , ) = explorer.getVaultPausedState();

        assertTrue(explorerIsPaused, "Explorer says Vault is not paused");
    }

    function testGetAggregateFeePercentages() public {
        _setProtocolFees();

        (uint256 aggregateSwapFeePercentage, uint256 aggregateYieldFeePercentage) = explorer.getAggregateFeePercentages(
            pool
        );

        assertEq(aggregateSwapFeePercentage, PROTOCOL_SWAP_FEE, "Wrong aggregate swap fee");
        assertEq(aggregateYieldFeePercentage, PROTOCOL_YIELD_FEE, "Wrong aggregate yield fee");
    }

    function testCollectAggregateFees() public {
        _setProtocolFees();

        // Check that the fee percentages are set in the pool.
        PoolConfig memory poolConfig = vault.getPoolConfig(pool);
        assertEq(poolConfig.aggregateSwapFeePercentage, PROTOCOL_SWAP_FEE);
        assertEq(poolConfig.aggregateYieldFeePercentage, PROTOCOL_YIELD_FEE);

        // Simulate incurred fees.
        vault.manualSetAggregateSwapFeeAmount(pool, dai, PROTOCOL_SWAP_FEE_AMOUNT);
        vault.manualSetAggregateYieldFeeAmount(pool, usdc, PROTOCOL_YIELD_FEE_AMOUNT);

        // Collected fees should initially be zero.
        uint256[] memory feeAmounts = feeController.getProtocolFeeAmounts(pool);
        assertEq(feeAmounts.length, 2, "Incorrect feeAmounts array");
        assertEq(feeAmounts[daiIdx], 0, "Non-zero DAI fees");
        assertEq(feeAmounts[usdcIdx], 0, "Non-zero USDC fees");

        // Collect through the explorer.
        explorer.collectAggregateFees(pool);

        // Ensure they were actually collected.
        feeAmounts = feeController.getProtocolFeeAmounts(pool);
        assertTrue(feeAmounts[daiIdx] > 0, "Zero DAI fees");
        assertTrue(feeAmounts[usdcIdx] > 0, "Zero USDC fees");
    }

    function _setProtocolFees() private {
        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.setGlobalProtocolSwapFeePercentage.selector),
            admin
        );
        authorizer.grantRole(
            feeControllerAuth.getActionId(IProtocolFeeController.setGlobalProtocolYieldFeePercentage.selector),
            admin
        );

        vm.startPrank(admin);
        feeController.setGlobalProtocolSwapFeePercentage(PROTOCOL_SWAP_FEE);
        feeController.setGlobalProtocolYieldFeePercentage(PROTOCOL_YIELD_FEE);
        vm.stopPrank();

        // Permissionlessly update the pool's fee percentages.
        feeController.updateProtocolSwapFeePercentage(pool);
        feeController.updateProtocolYieldFeePercentage(pool);
    }

    function testGetBufferOwnerShares() public {
        _setupBuffer();

        uint256 lpShares = explorer.getBufferOwnerShares(waDAI, lp);
        assertTrue(lpShares > 0, "LP has no shares");
    }

    function testGetBufferTotalShares() public {
        _setupBuffer();

        uint256 lpShares = explorer.getBufferOwnerShares(waDAI, lp);
        uint256 totalShares = explorer.getBufferTotalShares(waDAI);

        // A single depositor has all the shares (except for the security premint).
        assertTrue(lpShares > 0, "LP has no shares");
        assertEq(totalShares - MIN_BPT, lpShares, "Share value mismatch");
    }

    function testGetBufferBalance() public {
        _setupBuffer();

        (uint256 vaultUnderlyingBalanceRaw, uint256 vaultWrappedBalanceRaw) = vault.getBufferBalance(waDAI);
        assertTrue(vaultUnderlyingBalanceRaw > 0, "Zero underlying balance");
        assertTrue(vaultWrappedBalanceRaw > 0, "Zero wrapped balance");

        (uint256 explorerUnderlyingBalanceRaw, uint256 explorertWrappedBalanceRaw) = explorer.getBufferBalance(waDAI);

        assertEq(explorerUnderlyingBalanceRaw, vaultUnderlyingBalanceRaw, "Underlying balance mismatch");
        assertEq(explorertWrappedBalanceRaw, vaultWrappedBalanceRaw, "Wrapped balance mismatch");
    }

    function _registerPool(address newPool, bool initializeNewPool) private {
        IERC20[] memory tokens = InputHelpers.sortTokens([address(dai), address(usdc)].toMemoryArray().asIERC20());

        PoolRoleAccounts memory roleAccounts;
        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(tokens);
        LiquidityManagement memory liquidityManagement;

        vault.registerPool(newPool, tokenConfig, 0, 0, false, roleAccounts, address(0), liquidityManagement);

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

        // `decimalScalingFactors` depends on balances array (it's used to calculate the number of tokens).
        uint256[] memory rawBalances = new uint256[](2);
        rawBalances[daiIdx] = DAI_RAW_BALANCE;
        rawBalances[usdcIdx] = USDC_RAW_BALANCE;

        vault.manualSetPoolTokensAndBalances(pool, tokens, rawBalances, rawBalances);

        PoolConfigBits originalPoolConfig;
        originalPoolConfig = originalPoolConfig
            .setTokenDecimalDiffs(PoolConfigLib.toTokenDecimalDiffs(tokenDecimalDiffs))
            .setPoolRegistered(true)
            .setPoolInitialized(true);

        vault.manualSetPoolConfigBits(pool, originalPoolConfig);
    }

    function _setupBuffer() private {
        vm.startPrank(lp);
        dai.mint(lp, defaultAmount);
        dai.approve(address(waDAI), defaultAmount);
        waDAI.deposit(defaultAmount, lp);

        waDAI.approve(address(permit2), MAX_UINT256);
        permit2.approve(address(waDAI), address(router), type(uint160).max, type(uint48).max);

        uint256 depositAmount = 100e18;

        router.addLiquidityToBuffer(IERC4626(address(waDAI)), depositAmount, depositAmount, lp);
        vm.stopPrank();
    }
}
