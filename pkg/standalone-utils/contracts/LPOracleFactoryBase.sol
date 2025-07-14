// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { ILPOracleFactoryBase } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/ILPOracleFactoryBase.sol";
import { ILPOracleBase } from "@balancer-labs/v3-interfaces/contracts/standalone-utils/ILPOracleBase.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { SingletonAuthentication } from "@balancer-labs/v3-vault/contracts/SingletonAuthentication.sol";

/**
 * @notice Base contract for deploying and managing pool oracles.
 * @dev The factories that inherit this contract must implement the `_create` function, which deploys a different
 * oracle, depending on the pool.
 */
abstract contract LPOracleFactoryBase is ILPOracleFactoryBase, SingletonAuthentication {
    uint256 internal _oracleVersion;
    bool internal _isDisabled;

    mapping(IBasePool pool => ILPOracleBase oracle) internal _oracles;
    mapping(ILPOracleBase oracle => bool creationFlag) internal _isOracleFromFactory;

    constructor(IVault vault, uint256 oracleVersion) SingletonAuthentication(vault) {
        _oracleVersion = oracleVersion;
    }

    /// @inheritdoc ILPOracleFactoryBase
    function create(IBasePool pool, AggregatorV3Interface[] memory feeds) external returns (ILPOracleBase oracle) {
        if (address(_oracles[pool]) != address(0)) {
            revert OracleAlreadyExists(pool, _oracles[pool]);
        }

        if (_isDisabled) {
            revert OracleFactoryDisabled();
        }

        IVault vault = getVault();
        IERC20[] memory tokens = vault.getPoolTokens(address(pool));

        InputHelpers.ensureInputLengthMatch(tokens.length, feeds.length);

        oracle = _create(vault, pool, feeds);
        _oracles[pool] = oracle;
        _isOracleFromFactory[oracle] = true;
    }

    /// @inheritdoc ILPOracleFactoryBase
    function getOracle(IBasePool pool) external view returns (ILPOracleBase oracle) {
        oracle = ILPOracleBase(address(_oracles[pool]));
    }

    /// @inheritdoc ILPOracleFactoryBase
    function isOracleFromFactory(ILPOracleBase oracle) external view returns (bool success) {
        success = _isOracleFromFactory[oracle];
    }

    /// @inheritdoc ILPOracleFactoryBase
    function disable() external authenticate {
        _isDisabled = true;
    }

    /// @inheritdoc ILPOracleFactoryBase
    function disableOracleFromPool(IBasePool pool) external authenticate {
        if (_isDisabled) {
            revert OracleFactoryDisabled();
        }

        ILPOracleBase oracle = _oracles[pool];

        if (address(oracle) == address(0)) {
            revert OracleDoesNotExists(pool);
        }

        _oracles[pool] = ILPOracleBase(address(0));
    }

    function _create(
        IVault vault,
        IBasePool pool,
        AggregatorV3Interface[] memory feeds
    ) internal virtual returns (ILPOracleBase oracle);
}
