// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IVaultExtension } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExtension.sol";
import { IVaultMainMock } from "@balancer-labs/v3-interfaces/contracts/test/IVaultMainMock.sol";
import { IAuthorizer } from "@balancer-labs/v3-interfaces/contracts/vault/IAuthorizer.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { EnumerableMap } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/EnumerableMap.sol";
import { ScalingHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ScalingHelpers.sol";

import { PoolConfigBits, PoolConfigLib } from "../lib/PoolConfigLib.sol";
import { PoolFactoryMock } from "./PoolFactoryMock.sol";
import { Vault } from "../Vault.sol";
import { VaultExtension } from "../VaultExtension.sol";
import { PackedTokenBalance } from "../lib/PackedTokenBalance.sol";

contract VaultMock is IVaultMainMock, Vault {
    using EnumerableMap for EnumerableMap.IERC20ToBytes32Map;
    using ScalingHelpers for uint256;
    using PackedTokenBalance for bytes32;
    using PoolConfigLib for PoolConfig;

    PoolFactoryMock private immutable _poolFactoryMock;

    bytes32 private constant _ALL_BITS_SET = bytes32(type(uint256).max);

    constructor(IVaultExtension vaultExtension, IAuthorizer authorizer) Vault(vaultExtension, authorizer) {
        uint256 pauseWindowEndTime = IVaultAdmin(address(vaultExtension)).getPauseWindowEndTime();
        uint256 bufferPeriodDuration = IVaultAdmin(address(vaultExtension)).getBufferPeriodDuration();
        _poolFactoryMock = new PoolFactoryMock(IVault(address(this)), pauseWindowEndTime - bufferPeriodDuration);
    }

    function getPoolFactoryMock() external view returns (address) {
        return address(_poolFactoryMock);
    }

    function burnERC20(address token, address from, uint256 amount) external {
        _burn(token, from, amount);
    }

    function mintERC20(address token, address to, uint256 amount) external {
        _mint(token, to, amount);
    }

    function setConfig(address pool, PoolConfig calldata config) external {
        _poolConfig[pool] = config.fromPoolConfig();
    }

    // Used for testing pool registration, which is ordinarily done in the pool factory.
    // The Mock pool has an argument for whether or not to register on deployment. To call register pool
    // separately, deploy it with the registration flag false, then call this function.
    function manualRegisterPool(address pool, IERC20[] memory tokens) external whenVaultNotPaused {
        _poolFactoryMock.registerPool(
            pool,
            buildTokenConfig(tokens),
            address(0),
            PoolConfigBits.wrap(0).toPoolConfig().hooks,
            PoolConfigBits.wrap(_ALL_BITS_SET).toPoolConfig().liquidityManagement
        );
    }

    function manualRegisterPoolWithSwapFee(
        address pool,
        IERC20[] memory tokens,
        uint256 swapFeePercentage
    ) external whenVaultNotPaused {
        _poolFactoryMock.registerPoolWithSwapFee(
            pool,
            buildTokenConfig(tokens),
            swapFeePercentage,
            address(0),
            PoolConfigBits.wrap(0).toPoolConfig().hooks,
            PoolConfigBits.wrap(_ALL_BITS_SET).toPoolConfig().liquidityManagement
        );
    }

    function manualRegisterPoolPassThruTokens(address pool, IERC20[] memory tokens) external {
        TokenConfig[] memory tokenConfig = new TokenConfig[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            tokenConfig[i].token = tokens[i];
        }

        _poolFactoryMock.registerPool(
            pool,
            tokenConfig,
            address(0),
            PoolConfigBits.wrap(0).toPoolConfig().hooks,
            PoolConfigBits.wrap(_ALL_BITS_SET).toPoolConfig().liquidityManagement
        );
    }

    function manualRegisterPoolAtTimestamp(
        address pool,
        IERC20[] memory tokens,
        uint256 timestamp,
        address pauseManager
    ) external whenVaultNotPaused {
        _poolFactoryMock.registerPoolAtTimestamp(
            pool,
            buildTokenConfig(tokens),
            pauseManager,
            PoolConfigBits.wrap(0).toPoolConfig().hooks,
            PoolConfigBits.wrap(_ALL_BITS_SET).toPoolConfig().liquidityManagement,
            timestamp
        );
    }

    function buildTokenConfig(IERC20[] memory tokens) public pure returns (TokenConfig[] memory tokenConfig) {
        tokenConfig = new TokenConfig[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            tokenConfig[i].token = tokens[i];
        }

        tokenConfig = sortTokenConfig(tokenConfig);
    }

    function buildTokenConfig(
        IERC20[] memory tokens,
        IRateProvider[] memory rateProviders
    ) public pure returns (TokenConfig[] memory tokenConfig) {
        tokenConfig = new TokenConfig[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            tokenConfig[i].token = tokens[i];
            tokenConfig[i].rateProvider = rateProviders[i];
            tokenConfig[i].tokenType = rateProviders[i] == IRateProvider(address(0))
                ? TokenType.STANDARD
                : TokenType.WITH_RATE;
        }

        tokenConfig = sortTokenConfig(tokenConfig);
    }

    function buildTokenConfig(
        IERC20[] memory tokens,
        IRateProvider[] memory rateProviders,
        bool[] memory yieldExemptFlags
    ) public pure returns (TokenConfig[] memory tokenConfig) {
        tokenConfig = new TokenConfig[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            tokenConfig[i].token = tokens[i];
            tokenConfig[i].rateProvider = rateProviders[i];
            tokenConfig[i].tokenType = rateProviders[i] == IRateProvider(address(0))
                ? TokenType.STANDARD
                : TokenType.WITH_RATE;
            tokenConfig[i].yieldFeeExempt = yieldExemptFlags[i];
        }

        tokenConfig = sortTokenConfig(tokenConfig);
    }

    function buildTokenConfig(
        IERC20[] memory tokens,
        TokenType[] memory tokenTypes,
        IRateProvider[] memory rateProviders,
        bool[] memory yieldExemptFlags
    ) public pure returns (TokenConfig[] memory tokenConfig) {
        tokenConfig = new TokenConfig[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            tokenConfig[i].token = tokens[i];
            tokenConfig[i].tokenType = tokenTypes[i];
            tokenConfig[i].rateProvider = rateProviders[i];
            tokenConfig[i].yieldFeeExempt = yieldExemptFlags[i];
        }

        tokenConfig = sortTokenConfig(tokenConfig);
    }

    function getDecimalScalingFactors(address pool) external view returns (uint256[] memory) {
        PoolConfig memory config = _poolConfig[pool].toPoolConfig();
        IERC20[] memory tokens = _getPoolTokens(pool);

        return PoolConfigLib.getDecimalScalingFactors(config, tokens.length);
    }

    function recoveryModeExit(address pool) external view onlyInRecoveryMode(pool) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function computePoolDataUpdatingBalancesAndFees(
        address pool,
        Rounding roundingDirection
    ) external returns (PoolData memory) {
        return _computePoolDataUpdatingBalancesAndFees(pool, roundingDirection);
    }

    function updateLiveTokenBalanceInPoolData(
        PoolData memory poolData,
        Rounding roundingDirection,
        uint256 tokenIndex
    ) external pure returns (PoolData memory) {
        _updateLiveTokenBalanceInPoolData(poolData, roundingDirection, tokenIndex);
        return poolData;
    }

    function computeYieldProtocolFeesDue(
        PoolData memory poolData,
        uint256 lastLiveBalance,
        uint256 tokenIndex,
        uint256 yieldFeePercentage
    ) external pure returns (uint256) {
        return _computeYieldProtocolFeesDue(poolData, lastLiveBalance, tokenIndex, yieldFeePercentage);
    }

    function getRawBalances(address pool) external view returns (uint256[] memory balancesRaw) {
        EnumerableMap.IERC20ToBytes32Map storage poolTokenBalances = _poolTokenBalances[pool];

        uint256 numTokens = poolTokenBalances.length();
        balancesRaw = new uint256[](numTokens);
        bytes32 packedBalances;

        for (uint256 i = 0; i < numTokens; i++) {
            (, packedBalances) = poolTokenBalances.unchecked_at(i);
            balancesRaw[i] = packedBalances.getRawBalance();
        }
    }

    function getCurrentLiveBalances(address pool) external view returns (uint256[] memory currentLiveBalances) {
        EnumerableMap.IERC20ToBytes32Map storage poolTokenBalances = _poolTokenBalances[pool];
        PoolData memory poolData;

        (
            poolData.tokenConfig,
            poolData.balancesRaw,
            poolData.decimalScalingFactors,
            poolData.poolConfig
        ) = _getPoolTokenInfo(pool);

        _updateTokenRatesInPoolData(poolData);

        uint256 numTokens = poolTokenBalances.length();
        currentLiveBalances = new uint256[](numTokens);
        bytes32 packedBalances;

        for (uint256 i = 0; i < numTokens; i++) {
            (, packedBalances) = poolTokenBalances.unchecked_at(i);
            currentLiveBalances[i] = packedBalances.getRawBalance().toScaled18ApplyRateRoundDown(
                poolData.decimalScalingFactors[i],
                poolData.tokenRates[i]
            );
        }
    }

    function getLastLiveBalances(address pool) external view returns (uint256[] memory lastLiveBalances) {
        EnumerableMap.IERC20ToBytes32Map storage poolTokenBalances = _poolTokenBalances[pool];

        uint256 numTokens = poolTokenBalances.length();
        lastLiveBalances = new uint256[](numTokens);
        bytes32 packedBalances;

        for (uint256 i = 0; i < numTokens; i++) {
            (, packedBalances) = poolTokenBalances.unchecked_at(i);
            lastLiveBalances[i] = packedBalances.getLastLiveBalanceScaled18();
        }
    }

    function sortTokenConfig(TokenConfig[] memory tokenConfig) public pure returns (TokenConfig[] memory) {
        for (uint256 i = 0; i < tokenConfig.length - 1; i++) {
            for (uint256 j = 0; j < tokenConfig.length - i - 1; j++) {
                if (tokenConfig[j].token > tokenConfig[j + 1].token) {
                    // Swap if they're out of order.
                    (tokenConfig[j], tokenConfig[j + 1]) = (tokenConfig[j + 1], tokenConfig[j]);
                }
            }
        }

        return tokenConfig;
    }

    function guardedCheckEntered() external nonReentrant {
        require(reentrancyGuardEntered());
    }

    function unguardedCheckNotEntered() external view {
        require(!reentrancyGuardEntered());
    }
}
