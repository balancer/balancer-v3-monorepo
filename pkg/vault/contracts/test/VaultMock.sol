// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { Vault } from "../Vault.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import { PoolConfig, LiquidityManagementDefaults } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IAuthorizer } from "@balancer-labs/v3-interfaces/contracts/vault/IAuthorizer.sol";

import { Asset, AssetHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/AssetHelpers.sol";

import { PoolConfigBits, PoolConfigLib } from "../lib/PoolConfigLib.sol";

contract VaultMock is Vault {
    using PoolConfigLib for PoolConfig;

    constructor(
        IAuthorizer authorizer,
        uint256 pauseWindowDuration,
        uint256 bufferPeriodDuration
    ) Vault(authorizer, pauseWindowDuration, bufferPeriodDuration) {
        // solhint-disable-previous-line no-empty-blocks
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

    function pause() external {
        _pause();
    }

    // Used for testing the ReentrancyGuard
    function reentrantRegisterPool(address factory, IERC20[] memory tokens) external nonReentrant {
        this.registerPool(
            factory,
            tokens,
            PoolConfigBits.wrap(0).toPoolConfig().callbacks,
            PoolConfigBits.wrap(bytes32(type(uint256).max)).toPoolConfig().liquidityManagement
        );
    }

    // Used for testing pool registration, which is ordinarily done in the constructor of the pool.
    // The Mock pool has an argument for whether or not to register on deployment. To call register pool
    // separately, deploy it with the registration flag false, then call this function.
    function manualRegisterPool(address factory, IERC20[] memory tokens) external whenNotPaused {
        _registerPool(
            factory,
            tokens,
            PoolConfigBits.wrap(0).toPoolConfig().callbacks,
            PoolConfigBits.wrap(bytes32(type(uint256).max)).toPoolConfig().liquidityManagement,
            LiquidityManagementDefaults({
                supportsAddLiquidityProportional: true,
                supportsRemoveLiquidityProportional: true
            })
        );
    }
}
