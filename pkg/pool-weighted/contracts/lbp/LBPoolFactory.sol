// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IPoolVersion } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IPoolVersion.sol";
import { TokenConfig, PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { LBPParams } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPool.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import {
    ReentrancyGuardTransient
} from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/ReentrancyGuardTransient.sol";
import { BasePoolFactory } from "@balancer-labs/v3-pool-utils/contracts/BasePoolFactory.sol";
import { Version } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Version.sol";

import { LBPoolLib } from "../lib/LBPoolLib.sol";
import { LBPool } from "./LBPool.sol";

/**
 * @notice LBPool Factory.
 * @dev This is a factory specific to LBPools, allowing only two tokens and restricting the LBP to a single token sale,
 * with parameters specified on deployment.
 */
contract LBPoolFactory is IPoolVersion, ReentrancyGuardTransient, BasePoolFactory, Version {
    // LBPs are constrained to two tokens: project (the token being sold), and reserve (e.g., USDC or WETH).
    uint256 private constant _TWO_TOKENS = 2;

    string private _poolVersion;

    address internal immutable _trustedRouter;

    /**
     * @notice Emitted on deployment so that offchain processes know which token is which from the beginning.
     * @dev This information is also available onchain through immutable data and explicit getters on the pool.
     * @param pool The address of the new pool
     * @param projectToken The address of the project token (being distributed in the sale)
     * @param reserveToken The address of the reserve token (used to purchase the project token)
     */
    event LBPoolCreated(address indexed pool, IERC20 indexed projectToken, IERC20 indexed reserveToken);

    /// @notice The zero address was given for the trusted router.
    error InvalidTrustedRouter();

    /// @notice The owner is the zero address.
    error InvalidOwner();

    constructor(
        IVault vault,
        uint32 pauseWindowDuration,
        string memory factoryVersion,
        string memory poolVersion,
        address trustedRouter
    ) BasePoolFactory(vault, pauseWindowDuration, type(LBPool).creationCode) Version(factoryVersion) {
        if (trustedRouter == address(0)) {
            revert InvalidTrustedRouter();
        }

        // LBPools are deployed with a router known to reliably report the originating address on operations.
        // This is used to ensure that only the owner can add liquidity to an LBP.
        _trustedRouter = trustedRouter;

        _poolVersion = poolVersion;
    }

    /// @inheritdoc IPoolVersion
    function getPoolVersion() external view returns (string memory) {
        return _poolVersion;
    }

    /// @notice Returns trusted router, which is the gateway to add liquidity to the pool.
    function getTrustedRouter() external view returns (address) {
        return _trustedRouter;
    }

    /**
     * @notice Deploys a new `LBPool`.
     * @dev This method does not support native ETH management; WETH needs to be used instead.
     * @param name The name of the pool
     * @param symbol The symbol of the pool
     * @param lbpParams The LBP configuration (see ILBPool for the struct definition)
     * @param swapFeePercentage Initial swap fee percentage (bound by the WeightedPool range)
     * @param salt The salt value that will be passed to create3 deployment
     */
    function create(
        string memory name,
        string memory symbol,
        LBPParams memory lbpParams,
        uint256 swapFeePercentage,
        bytes32 salt
    ) external nonReentrant returns (address pool) {
        if (lbpParams.owner == address(0)) {
            revert InvalidOwner();
        }

        PoolRoleAccounts memory roleAccounts;

        // This account can change the static swap fee for the pool.
        roleAccounts.swapFeeManager = lbpParams.owner;

        // Validate weight parameters and temporal constraints prior to deployment.
        // This validation is duplicated in the pool contract but performed here to surface precise error messages,
        // as create2 would otherwise mask the underlying revert reason.
        LBPoolLib.verifyWeightUpdateParameters(
            lbpParams.startTime,
            lbpParams.endTime,
            lbpParams.projectTokenStartWeight,
            lbpParams.reserveTokenStartWeight,
            lbpParams.projectTokenEndWeight,
            lbpParams.reserveTokenEndWeight
        );

        pool = _create(abi.encode(name, symbol, lbpParams, getVault(), _trustedRouter, _poolVersion), salt);

        emit LBPoolCreated(pool, lbpParams.projectToken, lbpParams.reserveToken);

        _registerPoolWithVault(
            pool,
            _buildTokenConfig(lbpParams.projectToken, lbpParams.reserveToken),
            swapFeePercentage,
            false, // not exempt from protocol fees
            roleAccounts,
            pool, // register the pool itself as the hook contract
            getDefaultLiquidityManagement()
        );
    }

    function _buildTokenConfig(
        IERC20 projectToken,
        IERC20 reserveToken
    ) private pure returns (TokenConfig[] memory tokenConfig) {
        tokenConfig = new TokenConfig[](_TWO_TOKENS);

        (tokenConfig[0].token, tokenConfig[1].token) = projectToken < reserveToken
            ? (projectToken, reserveToken)
            : (reserveToken, projectToken);
    }
}
