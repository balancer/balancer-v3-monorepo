// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { ISequencerUptimeFeed } from "@balancer-labs/v3-interfaces/contracts/oracles/ISequencerUptimeFeed.sol";
import { ILPOracleFactoryBase } from "@balancer-labs/v3-interfaces/contracts/oracles/ILPOracleFactoryBase.sol";
import { ILPOracleBase } from "@balancer-labs/v3-interfaces/contracts/oracles/ILPOracleBase.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { SingletonAuthentication } from "@balancer-labs/v3-vault/contracts/SingletonAuthentication.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { Version } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Version.sol";

/**
 * @notice Base contract for deploying and managing pool oracles.
 * @dev The factories that inherit this contract must implement the `_create` function, which deploys a different
 * oracle, depending on the pool.
 */
abstract contract LPOracleFactoryBase is ILPOracleFactoryBase, ISequencerUptimeFeed, SingletonAuthentication, Version {
    // Used to ensure the L2 sequencer (on networks that have one) is live, and has been operating long enough to
    // accurately reflect the state. These values are passed to the oracle contracts on creation.
    AggregatorV3Interface internal immutable _sequencerUptimeFeed;
    uint256 internal immutable _uptimeResyncWindow;

    uint256 internal _oracleVersion;
    bool internal _isDisabled;

    mapping(bytes32 oracleId => ILPOracleBase oracle) internal _oracles;
    mapping(ILPOracleBase oracle => bool creationFlag) internal _isOracleFromFactory;

    constructor(
        IVault vault,
        AggregatorV3Interface sequencerUptimeFeed,
        uint256 uptimeResyncWindow,
        string memory factoryVersion,
        uint256 oracleVersion
    ) SingletonAuthentication(vault) Version(factoryVersion) {
        // The uptime feed address will be zero for L1, and for L2 networks that don't have a sequencer.
        _sequencerUptimeFeed = sequencerUptimeFeed;
        _uptimeResyncWindow = uptimeResyncWindow;

        _oracleVersion = oracleVersion;
    }

    /// @inheritdoc ILPOracleFactoryBase
    function getOracleVersion() external view returns (uint256) {
        return _oracleVersion;
    }

    /// @inheritdoc ILPOracleFactoryBase
    function create(IBasePool pool, AggregatorV3Interface[] memory feeds) external returns (ILPOracleBase oracle) {
        _ensureEnabled();

        bytes32 oracleId = _computeOracleId(pool, feeds);

        if (address(_oracles[oracleId]) != address(0)) {
            revert OracleAlreadyExists(pool, feeds, _oracles[oracleId]);
        }

        IVault vault = getVault();
        IERC20[] memory tokens = vault.getPoolTokens(address(pool));

        InputHelpers.ensureInputLengthMatch(tokens.length, feeds.length);

        oracle = _create(vault, pool, feeds);
        _oracles[oracleId] = oracle;
        _isOracleFromFactory[oracle] = true;
    }

    /// @inheritdoc ILPOracleFactoryBase
    function getOracle(
        IBasePool pool,
        AggregatorV3Interface[] memory feeds
    ) external view returns (ILPOracleBase oracle) {
        bytes32 oracleId = _computeOracleId(pool, feeds);
        oracle = ILPOracleBase(address(_oracles[oracleId]));
    }

    /// @inheritdoc ILPOracleFactoryBase
    function isOracleFromFactory(ILPOracleBase oracle) external view returns (bool success) {
        success = _isOracleFromFactory[oracle];
    }

    /// @inheritdoc ISequencerUptimeFeed
    function getSequencerUptimeFeed() external view returns (AggregatorV3Interface sequencerUptimeFeed) {
        return _sequencerUptimeFeed;
    }

    /// @inheritdoc ISequencerUptimeFeed
    function getUptimeResyncWindow() external view returns (uint256 uptimeResyncWindow) {
        return _uptimeResyncWindow;
    }

    /// @inheritdoc ILPOracleFactoryBase
    function disable() external authenticate {
        _ensureEnabled();

        _isDisabled = true;
        emit OracleFactoryDisabled();
    }

    function _computeOracleId(IBasePool pool, AggregatorV3Interface[] memory feeds) internal pure returns (bytes32) {
        address[] memory feedAddresses = _asAddress(feeds);
        return keccak256(abi.encode(pool, feedAddresses));
    }

    function _ensureEnabled() internal view {
        if (_isDisabled) {
            revert OracleFactoryIsDisabled();
        }
    }

    function _asAddress(AggregatorV3Interface[] memory feeds) internal pure returns (address[] memory addresses) {
        // solhint-disable-next-line no-inline-assembly
        assembly ("memory-safe") {
            addresses := feeds
        }
    }

    /// @dev Implementations of this function should also emit a specific event according to the oracle type.
    function _create(
        IVault vault,
        IBasePool pool,
        AggregatorV3Interface[] memory feeds
    ) internal virtual returns (ILPOracleBase oracle);
}
