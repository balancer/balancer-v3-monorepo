// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { ISwapFeePercentageBounds } from "@balancer-labs/v3-interfaces/contracts/vault/ISwapFeePercentageBounds.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import { IVaultMock } from "@balancer-labs/v3-interfaces/contracts/test/IVaultMock.sol";
import { TokenInfo, TokenType, PoolConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { CastingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/CastingHelpers.sol";
import { VaultMockDeployer } from "@balancer-labs/v3-vault/test/foundry/utils/VaultMockDeployer.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { BaseTest } from "@balancer-labs/v3-solidity-utils/test/foundry/utils/BaseTest.sol";

import { PoolInfo } from "../../contracts/PoolInfo.sol";

contract PoolInfoTest is BaseTest {
    using CastingHelpers for address[];
    using ArrayHelpers for *;

    IVaultMock vault;
    PoolInfo poolInfo;
    IERC20[] poolTokens;

    function setUp() public override {
        super.setUp();
        vault = IVaultMock(address(VaultMockDeployer.deploy()));
        poolInfo = new PoolInfo(vault);
        poolTokens = InputHelpers.sortTokens([address(dai), address(usdc)].toMemoryArray().asIERC20());

        vm.mockCall(
            address(poolInfo),
            abi.encodeWithSelector(ISwapFeePercentageBounds.getMinimumSwapFeePercentage.selector),
            abi.encode(0)
        );
        vm.mockCall(
            address(poolInfo),
            abi.encodeWithSelector(ISwapFeePercentageBounds.getMaximumSwapFeePercentage.selector),
            abi.encode(FixedPoint.ONE) // 100%
        );
        vault.manualRegisterPool(address(poolInfo), poolTokens);
    }

    function testGetTokens() public view {
        IERC20[] memory actualTokens = poolInfo.getTokens();
        assertEq(actualTokens.length, 2, "Incorrect token length");
        assertEq(address(actualTokens[0]), address(poolTokens[0]), "Incorrect token 0");
        assertEq(address(actualTokens[1]), address(poolTokens[1]), "Incorrect token 1");
    }

    function testGetTokenInfo() public {
        uint256[] memory expectedRawBalances = [uint256(1), uint256(2)].toMemoryArray();
        uint256[] memory expectedLastLiveBalances = [uint256(3), uint256(4)].toMemoryArray();
        vault.manualSetPoolTokensAndBalances(
            address(poolInfo),
            poolTokens,
            expectedRawBalances,
            expectedLastLiveBalances
        );

        TokenInfo[] memory expectedTokenInfo = new TokenInfo[](2);
        expectedTokenInfo[0] = TokenInfo({
            tokenType: TokenType.STANDARD,
            rateProvider: IRateProvider(address(123)),
            paysYieldFees: true
        });
        expectedTokenInfo[1] = TokenInfo({
            tokenType: TokenType.WITH_RATE,
            rateProvider: IRateProvider(address(4321)),
            paysYieldFees: false
        });
        vault.manualSetPoolTokenInfo(address(poolInfo), poolTokens, expectedTokenInfo);

        (
            IERC20[] memory actualTokens,
            TokenInfo[] memory tokenInfo,
            uint256[] memory balancesRaw,
            uint256[] memory lastBalancesLiveScaled18
        ) = poolInfo.getTokenInfo();

        // Tokens
        assertEq(actualTokens.length, 2, "Incorrect token length");
        assertEq(address(actualTokens[0]), address(poolTokens[0]), "Incorrect token 0");
        assertEq(address(actualTokens[1]), address(poolTokens[1]), "Incorrect token 1");

        // Token info
        assertEq(tokenInfo.length, 2, "Incorrect tokenInfo length");
        assertEq(
            uint256(tokenInfo[0].tokenType),
            uint256(expectedTokenInfo[0].tokenType),
            "Incorrect tokenInfo[0].tokenType"
        );
        assertEq(
            address(tokenInfo[0].rateProvider),
            address(expectedTokenInfo[0].rateProvider),
            "Incorrect tokenInfo[0].rateProvider"
        );
        assertEq(
            tokenInfo[0].paysYieldFees,
            expectedTokenInfo[0].paysYieldFees,
            "Incorrect tokenInfo[0].paysYieldFees"
        );
        assertEq(
            uint256(tokenInfo[1].tokenType),
            uint256(expectedTokenInfo[1].tokenType),
            "Incorrect tokenInfo[1].tokenType"
        );
        assertEq(
            address(tokenInfo[1].rateProvider),
            address(expectedTokenInfo[1].rateProvider),
            "Incorrect tokenInfo[1].rateProvider"
        );
        assertEq(
            tokenInfo[1].paysYieldFees,
            expectedTokenInfo[1].paysYieldFees,
            "Incorrect tokenInfo[1].paysYieldFees"
        );

        // Balances
        assertEq(balancesRaw.length, 2, "Incorrect balancesRaw length");
        assertEq(balancesRaw[0], expectedRawBalances[0], "Incorrect balancesRaw[0]");
        assertEq(balancesRaw[1], expectedRawBalances[1], "Incorrect balancesRaw[1]");
        assertEq(lastBalancesLiveScaled18.length, 2, "Incorrect lastBalancesLiveScaled18 length");
        assertEq(lastBalancesLiveScaled18[0], expectedLastLiveBalances[0], "Incorrect lastBalancesLiveScaled18[0]");
        assertEq(lastBalancesLiveScaled18[1], expectedLastLiveBalances[1], "Incorrect lastBalancesLiveScaled18[1]");
    }

    function testGetCurrentLiveBalances() public {
        uint256[] memory expectedRawBalances = [uint256(12), uint256(34)].toMemoryArray();
        uint256[] memory expectedLastLiveBalances = [uint256(56), uint256(478)].toMemoryArray();
        vault.manualSetPoolTokensAndBalances(
            address(poolInfo),
            poolTokens,
            expectedRawBalances,
            expectedLastLiveBalances
        );

        PoolConfig memory config;
        config.isPoolRegistered = true;
        vault.manualSetPoolConfig(address(poolInfo), config);

        // Expected == raw with this token config, for simplicity.
        uint256[] memory currentLiveBalances = poolInfo.getCurrentLiveBalances();
        assertEq(currentLiveBalances.length, 2, "Incorrect currentLiveBalances length");
        assertEq(currentLiveBalances[0], expectedRawBalances[0], "Incorrect currentLiveBalances[0]");
        assertEq(currentLiveBalances[1], expectedRawBalances[1], "Incorrect currentLiveBalances[1]");
    }

    function testGetStaticSwapFeePercentage() public {
        uint256 expectedSwapFeePercentage = 10e16; // 10%
        vault.manuallySetSwapFee(address(poolInfo), expectedSwapFeePercentage);

        uint256 swapFeePercentage = poolInfo.getStaticSwapFeePercentage();
        assertEq(swapFeePercentage, expectedSwapFeePercentage, "Incorrect swap fee percentage");
    }

    function testGetAggregateFeePercentages() public {
        // Use unusual values that aren't used anywhere else.
        uint256 expectedSwapFeePercentage = 32e16;
        uint256 expectedYieldFeePercentage = 21e16;

        vault.manualSetAggregateSwapFeePercentage(address(poolInfo), expectedSwapFeePercentage);
        vault.manualSetAggregateYieldFeePercentage(address(poolInfo), expectedYieldFeePercentage);

        (uint256 actualAggregateSwapFeePercentage, uint256 actualAggregateYieldFeePercentage) = poolInfo
            .getAggregateFeePercentages();

        assertEq(actualAggregateSwapFeePercentage, expectedSwapFeePercentage, "Incorrect swap fee percentage");
        assertEq(actualAggregateYieldFeePercentage, expectedYieldFeePercentage, "Incorrect yield fee percentage");
    }
}
