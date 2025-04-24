// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";

import { IBasePoolFactory } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePoolFactory.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { FactoryWidePauseWindow } from "@balancer-labs/v3-solidity-utils/contracts/helpers/FactoryWidePauseWindow.sol";

import { SingletonAuthentication } from "../SingletonAuthentication.sol";
import { PoolMock } from "./PoolMock.sol";

contract PoolFactoryMock is IBasePoolFactory, SingletonAuthentication, FactoryWidePauseWindow {
    uint256 private constant DEFAULT_SWAP_FEE = 0;

    IVault private immutable _vault;

    // Avoid dependency on BasePoolFactory; copy storage here.
    mapping(address pool => bool isFromFactory) private _isPoolFromFactory;
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

    function registerPoolWithHook(address pool, TokenConfig[] memory tokenConfig, address poolHooksContract) external {
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

    function manualSetPoolFromFactory(address pool) external {
        _isPoolFromFactory[pool] = true;
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

    function getPoolCount() external pure returns (uint256) {
        revert("Not implemented");
    }

    function getPools() external pure returns (address[] memory) {
        revert("Not implemented");
    }

    function getPoolsInRange(uint256, uint256) external pure returns (address[] memory) {
        revert("Not implemented");
    }

    /// @inheritdoc IBasePoolFactory
    function isDisabled() public view returns (bool) {
        return _disabled;
    }

    /// @inheritdoc IBasePoolFactory
    function getDeploymentAddress(
        bytes memory constructorArgs,
        bytes32 salt
    ) public view returns (address deployAddress) {
        bytes memory creationCode = abi.encodePacked(type(PoolMock).creationCode, constructorArgs);
        bytes32 creationCodeHash = keccak256(creationCode);
        bytes32 finalSalt = _computeFinalSalt(salt);

        return Create2.computeAddress(finalSalt, creationCodeHash, address(this));
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
