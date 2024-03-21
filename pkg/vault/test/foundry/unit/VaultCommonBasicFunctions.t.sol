// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { PoolConfigLib } from "../../../contracts/lib/PoolConfigLib.sol";

import { BaseVaultTest } from "../utils/BaseVaultTest.sol";

contract VaultCommonBasicFunctionsTest is BaseVaultTest {
    using PoolConfigLib for PoolConfig;
    using SafeCast for uint256;

    // The balance and live balance are stored in the same bytes32 word, each uses 128 bits
    uint256 private constant _MAX_RAW_BALANCE = 2 ** 128 - 1;

    function setUp() public virtual override {
        BaseVaultTest.setUp();
    }

    /*******************************************************************************
                                  _getPoolTokenInfo
    *******************************************************************************/

    function testEmptyPoolTokenConfig() public {
        // Generates a "random" address for a non-existent pool
        address newPool = address(bytes20(keccak256(abi.encode(block.timestamp))));
        (TokenConfig[] memory newTokenConfig, , , ) = vault.internalGetPoolTokenInfo(newPool);
        assertEq(newTokenConfig.length, 0, 'newTokenConfig should be empty');
    }

    function testNonEmptyPoolTokenConfig() public {
        // Generates a "random" address for a non-existent pool
        address newPool = address(bytes20(keccak256(abi.encode(block.timestamp))));
        IERC20[] memory tokens = new IERC20[](3);
        tokens[0] = usdc;
        tokens[1] = dai;
        tokens[2] = wsteth;
        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(tokens);
        vault.manualSetPoolTokenConfig(newPool, tokens, tokenConfig);
        uint256[] memory rawBalances = new uint256[](3);
        vault.manualSetPoolTokenBalances(newPool, tokens, rawBalances);

        (TokenConfig[] memory newTokenConfig, , , ) = vault.internalGetPoolTokenInfo(newPool);
        assertEq(newTokenConfig.length, 3);
        for (uint256 i = 0; i < newTokenConfig.length; i++) {
            assertEq(address(newTokenConfig[i].token), address(tokens[i]), string.concat('token', Strings.toString(i), 'address is not correct'));
            assertEq(uint256(newTokenConfig[i].tokenType), uint256(TokenType.STANDARD), string.concat('token', Strings.toString(i), 'should be STANDARD type'));
            assertEq(address(newTokenConfig[i].rateProvider), address(0), string.concat('token', Strings.toString(i), 'should have no rate provider'));
            assertEq(newTokenConfig[i].yieldFeeExempt, false, string.concat('token', Strings.toString(i), 'yieldFeeExempt flag should be false'));
        }
    }

    function testNonEmptyPoolTokenBalance() public {
        // Generates a "random" address for a non-existent pool
        address newPool = address(bytes20(keccak256(abi.encode(block.timestamp))));
        IERC20[] memory tokens = new IERC20[](3);
        tokens[0] = usdc;
        tokens[1] = dai;
        tokens[2] = wsteth;
        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(tokens);
        vault.manualSetPoolTokenConfig(newPool, tokens, tokenConfig);
        uint256[] memory originalBalancesRaw = new uint256[](3);
        originalBalancesRaw[0] = 1000;
        originalBalancesRaw[1] = 2000;
        originalBalancesRaw[2] = 3000;
        vault.manualSetPoolTokenBalances(newPool, tokens, originalBalancesRaw);

        (TokenConfig[] memory newTokenConfig, uint256[] memory balancesRaw, , ) = vault.internalGetPoolTokenInfo(
            newPool
        );
        assertEq(newTokenConfig.length, 3);
        assertEq(balancesRaw.length, 3);
        for (uint256 i = 0; i < newTokenConfig.length; i++) {
            assertEq(address(newTokenConfig[i].token), address(tokens[i]), string.concat('token', Strings.toString(i), 'address is not correct'));
            assertEq(uint256(newTokenConfig[i].tokenType), uint256(TokenType.STANDARD), string.concat('token', Strings.toString(i), 'should be STANDARD type'));
            assertEq(address(newTokenConfig[i].rateProvider), address(0), string.concat('token', Strings.toString(i), 'should have no rate provider'));
            assertEq(newTokenConfig[i].yieldFeeExempt, false, string.concat('token', Strings.toString(i), 'yieldFeeExempt flag should be false'));

            assertEq(balancesRaw[i], originalBalancesRaw[i], string.concat('token', Strings.toString(i), 'balance should match set pool balance'));
        }
    }

    function testEmptyPoolConfig() public {
        // Generates a "random" address for a non-existent pool
        address newPool = address(bytes20(keccak256(abi.encode(block.timestamp))));
        PoolConfig memory emptyPoolConfig;

        (, , uint256[] memory decimalScalingFactors, PoolConfig memory poolConfig) = vault.internalGetPoolTokenInfo(
            newPool
        );
        assertEq(decimalScalingFactors.length, 0, 'should have no decimalScalingFactors');
        assertEq(
            bytes32(sha256(abi.encodePacked(poolConfig.fromPoolConfig()))),
            bytes32(sha256(abi.encodePacked(emptyPoolConfig.fromPoolConfig()))),
            'poolConfig should match empty pool config'
        );
    }

    function testNonEmptyPoolConfig() public {
        // Generates a "random" address for a non-existent pool
        address newPool = address(bytes20(keccak256(abi.encode(block.timestamp))));

        IERC20[] memory tokens = new IERC20[](3);
        tokens[0] = usdc;
        tokens[1] = dai;
        tokens[2] = wsteth;
        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(tokens);
        vault.manualSetPoolTokenConfig(newPool, tokens, tokenConfig);

        // decimalScalingFactors depends on balances array (it's used gto calculate number of tokens)
        uint256[] memory rawBalances = new uint256[](3);
        rawBalances[0] = 1000;
        rawBalances[1] = 2000;
        rawBalances[2] = 3000;
        vault.manualSetPoolTokenBalances(newPool, tokens, rawBalances);

        PoolConfig memory originalPoolConfig;
        uint8[] memory tokenDecimalDiffs = new uint8[](3);
        tokenDecimalDiffs[0] = 12;
        tokenDecimalDiffs[1] = 10;
        tokenDecimalDiffs[2] = 0;
        originalPoolConfig.tokenDecimalDiffs = PoolConfigLib.toTokenDecimalDiffs(tokenDecimalDiffs);
        vault.manualSetPoolConfig(newPool, originalPoolConfig);

        (, , uint256[] memory decimalScalingFactors, PoolConfig memory newPoolConfig) = vault
            .internalGetPoolTokenInfo(newPool);
        assertEq(decimalScalingFactors.length, 3, 'length of decimalScalingFactors should be equal to amount of tokens');
        for (uint256 i = 0; i < decimalScalingFactors.length; i++) {
            assertEq(decimalScalingFactors[i], 10 ** (18 + tokenDecimalDiffs[i]), string.concat('decimalScalingFactors of token', Strings.toString(i), 'should match tokenDecimalDiffs'));
        }
        assertEq(
            bytes32(sha256(abi.encodePacked(newPoolConfig.fromPoolConfig()))),
            bytes32(sha256(abi.encodePacked(originalPoolConfig.fromPoolConfig()))),
            'original and new poolConfigs should be the same'
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

        // Generates a "random" address for a non-existent pool
        address newPool = address(bytes20(keccak256(abi.encode(block.timestamp))));

        IERC20[] memory tokens = new IERC20[](3);
        tokens[0] = usdc;
        tokens[1] = dai;
        tokens[2] = wsteth;
        TokenConfig[] memory tokenConfig = vault.buildTokenConfig(tokens);
        vault.manualSetPoolTokenConfig(newPool, tokens, tokenConfig);

        // decimalScalingFactors depends on balances array (it's used gto calculate number of tokens)
        uint256[] memory originalBalancesRaw = new uint256[](3);
        originalBalancesRaw[0] = balance1;
        originalBalancesRaw[1] = balance2;
        originalBalancesRaw[2] = balance3;
        vault.manualSetPoolTokenBalances(newPool, tokens, originalBalancesRaw);

        PoolConfig memory originalPoolConfig;
        uint8[] memory tokenDecimalDiffs = new uint8[](3);
        tokenDecimalDiffs[0] = decimalDiff1;
        tokenDecimalDiffs[1] = decimalDiff2;
        tokenDecimalDiffs[2] = decimalDiff3;
        originalPoolConfig.tokenDecimalDiffs = PoolConfigLib.toTokenDecimalDiffs(tokenDecimalDiffs);
        vault.manualSetPoolConfig(newPool, originalPoolConfig);

        (
            TokenConfig[] memory newTokenConfig,
            uint256[] memory balancesRaw,
            uint256[] memory decimalScalingFactors,
            PoolConfig memory newPoolConfig
        ) = vault.internalGetPoolTokenInfo(newPool);

        assertEq(newTokenConfig.length, 3);
        assertEq(balancesRaw.length, 3);
        assertEq(decimalScalingFactors.length, 3);

        for (uint256 i = 0; i < newTokenConfig.length; i++) {
            assertEq(address(newTokenConfig[i].token), address(tokens[i]), string.concat('token', Strings.toString(i), 'address is not correct'));
            assertEq(uint256(newTokenConfig[i].tokenType), uint256(TokenType.STANDARD), string.concat('token', Strings.toString(i), 'should be STANDARD type'));
            assertEq(address(newTokenConfig[i].rateProvider), address(0), string.concat('token', Strings.toString(i), 'should have no rate provider'));
            assertEq(newTokenConfig[i].yieldFeeExempt, false, string.concat('token', Strings.toString(i), 'yieldFeeExempt flag should be false'));

            assertEq(balancesRaw[i], originalBalancesRaw[i], string.concat('token', Strings.toString(i), 'balance should match set pool balance'));
            assertEq(decimalScalingFactors[i], 10 ** (18 + tokenDecimalDiffs[i]), string.concat('decimalScalingFactors of token', Strings.toString(i), 'should match tokenDecimalDiffs'));
        }

        assertEq(
            bytes32(sha256(abi.encodePacked(newPoolConfig.fromPoolConfig()))),
            bytes32(sha256(abi.encodePacked(originalPoolConfig.fromPoolConfig()))),
            'original and new poolConfigs should be the same'
        );
    }
}
