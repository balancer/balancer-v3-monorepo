// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IPoolVersion } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IPoolVersion.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { BasePoolFactory } from "@balancer-labs/v3-pool-utils/contracts/BasePoolFactory.sol";
import { Version } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Version.sol";

import { WeightedPool } from "./WeightedPool.sol";

/**
 * @notice Weighted Pool factory for 80/20 pools.
 * @dev These are standard Weighted Pools, but constrained to two tokens and 80/20 weights, greatly simplifying their
 * configuration. This is an example of a customized factory, designed to deploy special-purpose pools.
 *
 * It does not allow hooks, and has a custom salt computation that does not consider the deployer address.
 *
 * See https://medium.com/balancer-protocol/the-8020-initiative-64a7a6cab976 for one use case, and
 * https://medium.com/balancer-protocol/80-20-balancer-pools-ad7fed816c8d for a general discussion of the benefits of
 * 80/20 pools.
 */
contract WeightedPool8020Factory is IPoolVersion, BasePoolFactory, Version {
    uint256 private constant _EIGHTY = 80e16; // 80%
    uint256 private constant _TWENTY = 20e16; // 20%

    string private _poolVersion;

    constructor(
        IVault vault,
        uint32 pauseWindowDuration,
        string memory factoryVersion,
        string memory poolVersion
    ) BasePoolFactory(vault, pauseWindowDuration, type(WeightedPool).creationCode) Version(factoryVersion) {
        _poolVersion = poolVersion;
    }

    /// @inheritdoc IPoolVersion
    function getPoolVersion() external view returns (string memory) {
        return _poolVersion;
    }

    /**
     * @notice Deploys a new `WeightedPool`.
     * @dev Since tokens must be sorted, pass in explicit 80/20 token config structs.
     * @param highWeightTokenConfig The token configuration of the high weight token
     * @param lowWeightTokenConfig The token configuration of the low weight token
     * @param roleAccounts Addresses the Vault will allow to change certain pool settings
     * @param swapFeePercentage Initial swap fee percentage
     */
    function create(
        TokenConfig memory highWeightTokenConfig,
        TokenConfig memory lowWeightTokenConfig,
        PoolRoleAccounts memory roleAccounts,
        uint256 swapFeePercentage
    ) external returns (address pool) {
        if (roleAccounts.poolCreator != address(0)) {
            revert StandardPoolWithCreator();
        }

        IERC20 highWeightToken = highWeightTokenConfig.token;
        IERC20 lowWeightToken = lowWeightTokenConfig.token;

        TokenConfig[] memory tokenConfig = new TokenConfig[](2);
        uint256[] memory weights = new uint256[](2);

        // Tokens must be sorted.
        (uint256 highWeightTokenIdx, uint256 lowWeightTokenIdx) = highWeightToken > lowWeightToken ? (1, 0) : (0, 1);

        weights[highWeightTokenIdx] = _EIGHTY;
        weights[lowWeightTokenIdx] = _TWENTY;

        tokenConfig[highWeightTokenIdx] = highWeightTokenConfig;
        tokenConfig[lowWeightTokenIdx] = lowWeightTokenConfig;

        string memory highWeightTokenSymbol = IERC20Metadata(address(highWeightToken)).symbol();
        string memory lowWeightTokenSymbol = IERC20Metadata(address(lowWeightToken)).symbol();

        pool = _create(
            abi.encode(
                WeightedPool.NewPoolParams({
                    name: string.concat("Balancer 80 ", highWeightTokenSymbol, " 20 ", lowWeightTokenSymbol),
                    symbol: string.concat("B-80", highWeightTokenSymbol, "-20", lowWeightTokenSymbol),
                    numTokens: 2,
                    normalizedWeights: weights,
                    version: _poolVersion
                }),
                getVault()
            ),
            _calculateSalt(highWeightToken, lowWeightToken)
        );

        // Using empty pool hooks for standard 80/20 pool.
        _registerPoolWithVault(
            pool,
            tokenConfig,
            swapFeePercentage,
            false, // not exempt from protocol fees
            roleAccounts,
            getDefaultPoolHooksContract(),
            getDefaultLiquidityManagement()
        );
    }

    /**
     * @notice Gets the address of the pool with the respective tokens and weights.
     * @param highWeightToken The token with 80% weight in the pool.
     * @param lowWeightToken The token with 20% weight in the pool.
     */
    function getPool(IERC20 highWeightToken, IERC20 lowWeightToken) external view returns (address pool) {
        bytes32 salt = _calculateSalt(highWeightToken, lowWeightToken);
        pool = getDeploymentAddress(salt);
    }

    function _calculateSalt(IERC20 highWeightToken, IERC20 lowWeightToken) internal view returns (bytes32 salt) {
        salt = keccak256(abi.encode(block.chainid, highWeightToken, lowWeightToken));
    }

    /**
     * @dev By default, the BasePoolFactory adds the sender and chainId to compute a final salt.
     * Override this to make it use the canonical address salt directly.
     */
    function _computeFinalSalt(bytes32 salt) internal pure override returns (bytes32) {
        return salt;
    }
}
