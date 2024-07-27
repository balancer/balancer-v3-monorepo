// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IBasePoolFactory } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePoolFactory.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import {
    SingletonAuthentication
} from "@balancer-labs/v3-solidity-utils/contracts/helpers/SingletonAuthentication.sol";
import { FactoryWidePauseWindow } from "@balancer-labs/v3-solidity-utils/contracts/helpers/FactoryWidePauseWindow.sol";
import { CREATE3 } from "@balancer-labs/v3-solidity-utils/contracts/solmate/CREATE3.sol";

import { PoolMock } from "./PoolMock.sol";

contract PoolFactoryMock is IBasePoolFactory, SingletonAuthentication, FactoryWidePauseWindow {
    uint256 private constant DEFAULT_SWAP_FEE = 0;

    IVault private immutable _vault;

    // Avoid dependency on BasePoolFactory; copy storage here.
    mapping(address => bool) private _isPoolFromFactory;
    bool private _disabled;

    constructor(
        IVault vault,
        uint32 pauseWindowDuration
    ) SingletonAuthentication(vault) FactoryWidePauseWindow(pauseWindowDuration) {
        _vault = vault;
    }

    function createPool(string memory name, string memory symbol) external returns (address) {
        PoolMock newPool = new PoolMock(IVault(address(_vault)), name, symbol);
        _registerPoolWithFactory(address(newPool));
        return address(newPool);
    }

    function registerTestPool(address pool, TokenConfig[] memory tokenConfig) external {
        PoolRoleAccounts memory roleAccounts;

        _vault.registerPool(
            pool,
            tokenConfig,
            DEFAULT_SWAP_FEE,
            getNewPoolPauseWindowEndTime(),
            false,
            roleAccounts,
            address(0), // No hook contract
            _getDefaultLiquidityManagement()
        );
    }

    function registerTestPool(address pool, TokenConfig[] memory tokenConfig, address poolHooksContract) external {
        PoolRoleAccounts memory roleAccounts;

        _vault.registerPool(
            pool,
            tokenConfig,
            DEFAULT_SWAP_FEE,
            getNewPoolPauseWindowEndTime(),
            false,
            roleAccounts,
            poolHooksContract,
            _getDefaultLiquidityManagement()
        );
    }

    function registerTestPool(
        address pool,
        TokenConfig[] memory tokenConfig,
        address poolHooksContract,
        address poolCreator
    ) external {
        PoolRoleAccounts memory roleAccounts;
        roleAccounts.poolCreator = poolCreator;

        _vault.registerPool(
            pool,
            tokenConfig,
            DEFAULT_SWAP_FEE,
            getNewPoolPauseWindowEndTime(),
            false,
            roleAccounts,
            poolHooksContract,
            _getDefaultLiquidityManagement()
        );
    }

    function registerGeneralTestPool(
        address pool,
        TokenConfig[] memory tokenConfig,
        uint256 swapFee,
        uint32 pauseWindowDuration,
        bool protocolFeeExempt,
        PoolRoleAccounts memory roleAccounts,
        address poolHooksContract
    ) external {
        _vault.registerPool(
            pool,
            tokenConfig,
            swapFee,
            uint32(block.timestamp) + pauseWindowDuration,
            protocolFeeExempt,
            roleAccounts,
            poolHooksContract,
            _getDefaultLiquidityManagement()
        );
    }

    function registerPool(
        address pool,
        TokenConfig[] memory tokenConfig,
        PoolRoleAccounts memory roleAccounts,
        address poolHooksContract,
        LiquidityManagement calldata liquidityManagement
    ) external {
        _vault.registerPool(
            pool,
            tokenConfig,
            DEFAULT_SWAP_FEE,
            getNewPoolPauseWindowEndTime(),
            false,
            roleAccounts,
            poolHooksContract,
            liquidityManagement
        );
    }

    function registerPoolWithSwapFee(
        address pool,
        TokenConfig[] memory tokenConfig,
        uint256 swapFeePercentage,
        address poolHooksContract,
        LiquidityManagement calldata liquidityManagement
    ) external {
        PoolRoleAccounts memory roleAccounts;

        _vault.registerPool(
            pool,
            tokenConfig,
            swapFeePercentage,
            getNewPoolPauseWindowEndTime(),
            false,
            roleAccounts,
            poolHooksContract,
            liquidityManagement
        );
    }

    // For tests; otherwise can't get the exact event arguments.
    function registerPoolAtTimestamp(
        address pool,
        TokenConfig[] memory tokenConfig,
        uint32 timestamp,
        PoolRoleAccounts memory roleAccounts,
        address poolHooksContract,
        LiquidityManagement calldata liquidityManagement
    ) external {
        _vault.registerPool(
            pool,
            tokenConfig,
            DEFAULT_SWAP_FEE,
            timestamp,
            false,
            roleAccounts,
            poolHooksContract,
            liquidityManagement
        );
    }

    function _getDefaultLiquidityManagement() private pure returns (LiquidityManagement memory) {
        LiquidityManagement memory liquidityManagement;
        liquidityManagement.enableAddLiquidityCustom = true;
        liquidityManagement.enableRemoveLiquidityCustom = true;
        return liquidityManagement;
    }

    /// @inheritdoc IBasePoolFactory
    function isPoolFromFactory(address pool) external view returns (bool) {
        return _isPoolFromFactory[pool];
    }

    /// @inheritdoc IBasePoolFactory
    function isDisabled() public view returns (bool) {
        return _disabled;
    }

    /// @inheritdoc IBasePoolFactory
    function getDeploymentAddress(bytes32 salt) public view returns (address) {
        return CREATE3.getDeployed(_computeFinalSalt(salt));
    }

    /// @inheritdoc IBasePoolFactory
    function disable() external authenticate {
        _ensureEnabled();

        _disabled = true;

        emit FactoryDisabled();
    }

    function _registerPoolWithFactory(address pool) internal virtual {
        _ensureEnabled();

        _isPoolFromFactory[pool] = true;

        emit PoolCreated(pool);
    }

    // Functions from BasePoolFactory

    function _ensureEnabled() internal view {
        if (isDisabled()) {
            revert Disabled();
        }
    }

    function _computeFinalSalt(bytes32 salt) internal view virtual returns (bytes32) {
        return keccak256(abi.encode(msg.sender, block.chainid, salt));
    }
}
