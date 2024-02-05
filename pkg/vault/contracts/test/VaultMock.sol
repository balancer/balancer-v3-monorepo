// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {
    TokenConfig,
    PoolConfig,
    PoolData,
    Rounding
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVaultExtension } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExtension.sol";
import { IVaultMainMock } from "@balancer-labs/v3-interfaces/contracts/test/IVaultMainMock.sol";
import { IAuthorizer } from "@balancer-labs/v3-interfaces/contracts/vault/IAuthorizer.sol";
import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";

import { EnumerableMap } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/EnumerableMap.sol";

import { PoolConfigBits, PoolConfigLib } from "../lib/PoolConfigLib.sol";
import { PoolFactoryMock } from "./PoolFactoryMock.sol";
import { Vault } from "../Vault.sol";
import { VaultExtension } from "../VaultExtension.sol";

contract VaultMock is IVaultMainMock, Vault {
    using EnumerableMap for EnumerableMap.IERC20ToUint256Map;
    using PoolConfigLib for PoolConfig;

    PoolFactoryMock private immutable _poolFactoryMock;

    bytes32 private constant _ALL_BITS_SET = bytes32(type(uint256).max);

    constructor(IVaultExtension vaultExtension, IAuthorizer authorizer) Vault(vaultExtension, authorizer) {
        uint256 pauseWindowEndTime = vaultExtension.getPauseWindowEndTime();
        uint256 bufferPeriodDuration = vaultExtension.getBufferPeriodDuration();
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

    function setRateProvider(address pool, IERC20 token, IRateProvider rateProvider) external {
        _poolRateProviders[pool][token] = rateProvider;
    }

    // Used for testing pool registration, which is ordinarily done in the pool factory.
    // The Mock pool has an argument for whether or not to register on deployment. To call register pool
    // separately, deploy it with the registration flag false, then call this function.
    function manualRegisterPool(address pool, IERC20[] memory tokens) external whenVaultNotPaused {
        IRateProvider[] memory rateProviders = new IRateProvider[](tokens.length);

        _poolFactoryMock.registerPool(
            pool,
            tokens,
            rateProviders,
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
        IRateProvider[] memory rateProviders = new IRateProvider[](tokens.length);

        _poolFactoryMock.registerPoolAtTimestamp(
            pool,
            tokens,
            rateProviders,
            pauseManager,
            PoolConfigBits.wrap(0).toPoolConfig().hooks,
            PoolConfigBits.wrap(_ALL_BITS_SET).toPoolConfig().liquidityManagement,
            timestamp
        );
    }

    function getDecimalScalingFactors(address pool) external view returns (uint256[] memory) {
        PoolConfig memory config = _poolConfig[pool].toPoolConfig();
        IERC20[] memory tokens = _getPoolTokens(pool);

        return PoolConfigLib.getDecimalScalingFactors(config, tokens.length);
    }

    function recoveryModeExit(address pool) external view onlyInRecoveryMode(pool) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function getPoolData(address pool, Rounding roundingDirection) external view returns (PoolData memory) {
        return _getPoolData(pool, roundingDirection);
    }

    function getRawBalances(address pool) external view returns (uint256[] memory balancesRaw) {
        EnumerableMap.IERC20ToUint256Map storage poolTokenBalances = _poolTokenBalances[pool];

        uint256 numTokens = poolTokenBalances.length();
        balancesRaw = new uint256[](numTokens);

        for (uint256 i = 0; i < numTokens; i++) {
            (, balancesRaw[i]) = poolTokenBalances.unchecked_at(i);
        }
    }
}
