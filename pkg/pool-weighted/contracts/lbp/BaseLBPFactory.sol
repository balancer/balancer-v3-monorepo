// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IPoolVersion } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IPoolVersion.sol";
import { LBPCommonParams } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPCommon.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import {
    ReentrancyGuardTransient
} from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/ReentrancyGuardTransient.sol";
import { BasePoolFactory } from "@balancer-labs/v3-pool-utils/contracts/BasePoolFactory.sol";
import { Version } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Version.sol";

import { LBPValidation } from "./LBPValidation.sol";

/**
 * @notice Base contract for LBP factories.
 * @dev This is a factory for LBPools, allowing only two tokens and restricting the LBP to a single token sale, with
 * common parameters specified on deployment. Derived LBP factories may have additional type-specific features.
 */
abstract contract BaseLBPFactory is IPoolVersion, BasePoolFactory, ReentrancyGuardTransient, Version {
    // LBPs are constrained to two tokens: project (the token being sold), and reserve (e.g., USDC or WETH).
    uint256 internal constant _TWO_TOKENS = 2;

    // The pool version and router addresses are stored in the factory and passed down to the pools on deployment.
    string internal _poolVersion;

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

    constructor(
        IVault vault,
        uint32 pauseWindowDuration,
        string memory factoryVersion,
        string memory poolVersion,
        address trustedRouter,
        bytes memory creationCode
    ) BasePoolFactory(vault, pauseWindowDuration, creationCode) Version(factoryVersion) {
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

    /**
     * @notice Returns trusted router, which is the gateway to add liquidity to the pool.
     * @return trustedRouter The address of the trusted router, guaranteed to reliably report the sender
     */
    function getTrustedRouter() external view returns (address) {
        return _trustedRouter;
    }

    // Helper function to create a `TokenConfig` array from the two LBP tokens.
    function _buildTokenConfig(
        IERC20 projectToken,
        IERC20 reserveToken
    ) internal pure returns (TokenConfig[] memory tokenConfig) {
        tokenConfig = new TokenConfig[](_TWO_TOKENS);

        (tokenConfig[0].token, tokenConfig[1].token) = projectToken < reserveToken
            ? (projectToken, reserveToken)
            : (reserveToken, projectToken);
    }

    function _registerLBP(
        address pool,
        LBPCommonParams memory lbpCommonParams,
        uint256 swapFeePercentage,
        address poolCreator
    ) internal {
        PoolRoleAccounts memory roleAccounts;
        LiquidityManagement memory liquidityManagement = getDefaultLiquidityManagement();
        liquidityManagement.disableUnbalancedLiquidity = true;

        // This account can change the static swap fee for the pool.
        roleAccounts.swapFeeManager = lbpCommonParams.owner;
        roleAccounts.poolCreator = poolCreator;

        _registerPoolWithVault(
            pool,
            _buildTokenConfig(lbpCommonParams.projectToken, lbpCommonParams.reserveToken),
            swapFeePercentage,
            false, // not exempt from protocol fees
            roleAccounts,
            pool, // register the pool itself as the hook contract
            liquidityManagement
        );
    }
}
