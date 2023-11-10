// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { Vault } from "../Vault.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import { PoolConfig } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IAuthorizer } from "@balancer-labs/v3-interfaces/contracts/vault/IAuthorizer.sol";

import { Asset, AssetHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/AssetHelpers.sol";

import { PoolConfigBits, PoolConfigLib } from "../lib/PoolConfigLib.sol";

import { PoolFactoryMock } from "./PoolFactoryMock.sol";

contract VaultMock is Vault {
    using PoolConfigLib for PoolConfig;

    PoolFactoryMock private immutable _poolFactoryMock;

    constructor(
        IAuthorizer authorizer,
        uint256 pauseWindowDuration,
        uint256 bufferPeriodDuration
    ) Vault(authorizer, pauseWindowDuration, bufferPeriodDuration) {
        _poolFactoryMock = new PoolFactoryMock(this, pauseWindowDuration, bufferPeriodDuration);
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

    function manualPauseVault() external {
        _setVaultPaused(true);
    }

    function manualUnpauseVault() external {
        _setVaultPaused(false);
    }

    function manualPausePool(address pool) external {
        _setPoolPaused(pool, true);
    }

    function manualUnpausePool(address pool) external {
        _setPoolPaused(pool, false);
    }

    // Used for testing the ReentrancyGuard
    function reentrantRegisterPool(address pool, IERC20[] memory tokens) external nonReentrant {
        this.registerPool(pool, tokens, 365 days, 30 days, PoolConfigBits.wrap(0).toPoolConfig().callbacks);
    }

    // Used for testing pool registration, which is ordinarily done in the pool factory.
    // The Mock pool has an argument for whether or not to register on deployment. To call register pool
    // separately, deploy it with the registration flag false, then call this function.
    function manualRegisterPool(address pool, IERC20[] memory tokens) external whenVaultNotPaused {
        _poolFactoryMock.registerPool(pool, tokens, PoolConfigBits.wrap(0).toPoolConfig().callbacks);
    }

    function getScalingFactors(address pool) external view returns (uint256[] memory) {
        PoolConfig memory config = _poolConfig[pool].toPoolConfig();
        (IERC20[] memory tokens, ) = _getPoolTokens(pool);

        return PoolConfigLib.getScalingFactors(config, tokens.length);
    }
}
