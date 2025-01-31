// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";

import { IPoolVersion } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IPoolVersion.sol";
import { TokenConfig, PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { LBPParams } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/ILBPool.sol";
import { IRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IRouter.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import {
    ReentrancyGuardTransient
} from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/ReentrancyGuardTransient.sol";
import { BasePoolFactory } from "@balancer-labs/v3-pool-utils/contracts/BasePoolFactory.sol";
import { Version } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Version.sol";

import { LBPool } from "./LBPool.sol";

//import { WeightedPool } from "../WeightedPool.sol";

/**
 * @notice LBPool Factory.
 * @dev This is a factory specific to LBPools, allowing only 2 tokens.
 */
contract LBPoolFactory is IPoolVersion, ReentrancyGuardTransient, BasePoolFactory, Version {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    // LBPs are constrained to two tokens: project and reserve.
    uint256 private constant _TWO_TOKENS = 2;

    string private _poolVersion;

    address internal immutable _trustedRouter;
    IPermit2 internal immutable _permit2;

    /// @notice The zero address was given for the trusted router.
    error InvalidTrustedRouter();

    constructor(
        IVault vault,
        uint32 pauseWindowDuration,
        string memory factoryVersion,
        string memory poolVersion,
        address trustedRouter,
        IPermit2 permit2
    ) BasePoolFactory(vault, pauseWindowDuration, type(LBPool).creationCode) Version(factoryVersion) {
        _poolVersion = poolVersion;

        if (trustedRouter == address(0)) {
            revert InvalidTrustedRouter();
        }

        // LBPools are deployed with a router known to reliably report the originating address on operations.
        // This is used to ensure that only the owner can add liquidity to an LBP (including on initialization).
        _trustedRouter = trustedRouter;

        // Allow one-step creation and initialization.
        _permit2 = permit2;
    }

    /// @inheritdoc IPoolVersion
    function getPoolVersion() external view returns (string memory) {
        return _poolVersion;
    }

    /// @notice Returns trusted router, which is the gateway to add liquidity to the pool.
    function getTrustedRouter() external view returns (address) {
        return _trustedRouter;
    }

    /// @notice Returns permit2 address, used to initialize pools.
    function getPermit2() external view returns (IPermit2) {
        return _permit2;
    }

    /**
     * @notice Deploys a new `LBPool`.
     * @dev Tokens must be sorted for pool registration.
     * @param name The name of the pool
     * @param symbol The symbol of the pool
     * @param lbpParams The LBP configuration (see LBPool)
     * @param swapFeePercentage Initial swap fee percentage
     * @param salt The salt value that will be passed to create3 deployment
     */
    function create(
        string memory name,
        string memory symbol,
        LBPParams memory lbpParams,
        uint256 swapFeePercentage,
        bytes32 salt
    ) external nonReentrant returns (address pool) {
        PoolRoleAccounts memory roleAccounts;

        roleAccounts.swapFeeManager = lbpParams.owner;

        pool = _create(abi.encode(name, symbol, lbpParams, getVault(), _trustedRouter, _poolVersion), salt);

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

    /**
     * @notice Deploys a new `LBPool` and seeds it with initial liquidity in the same tx.
     * @dev Tokens must be sorted for pool registration. Use this method in case pool initialization frontrunning
     * is an issue. If the owner is the only address with liquidity of one of the tokens, this should not be necessary.
     * This method does not support native ETH management; WETH needs to be used instead.
     *
     * @param name The name of the pool
     * @param symbol The symbol of the pool
     * @param lbpParams The LBP configuration (see LBPool)
     * @param swapFeePercentage Initial swap fee percentage
     * @param exactAmountsIn Token amounts in, sorted in token registration order
     * @param salt The salt value that will be passed to create3 deployment
     */
    function createAndInitialize(
        string memory name,
        string memory symbol,
        LBPParams memory lbpParams,
        uint256 swapFeePercentage,
        uint256[] memory exactAmountsIn,
        bytes32 salt
    ) external nonReentrant returns (address pool) {
        PoolRoleAccounts memory roleAccounts;

        roleAccounts.swapFeeManager = lbpParams.owner;

        pool = _create(abi.encode(name, symbol, lbpParams, getVault(), _trustedRouter, _poolVersion), salt);

        (uint256 projectTokenIndex, uint256 reserveTokenIndex) = lbpParams.projectToken < lbpParams.reserveToken
            ? (0, 1)
            : (1, 0);
        IERC20[] memory tokens = new IERC20[](_TWO_TOKENS);
        tokens[projectTokenIndex] = lbpParams.projectToken;
        tokens[reserveTokenIndex] = lbpParams.reserveToken;

        _prepareTokenInitialization(lbpParams.projectToken, exactAmountsIn[projectTokenIndex]);
        _prepareTokenInitialization(lbpParams.reserveToken, exactAmountsIn[reserveTokenIndex]);

        IRouter(_trustedRouter).initialize(pool, tokens, exactAmountsIn, 0, false, "");
    }

    function _prepareTokenInitialization(IERC20 token, uint256 exactAmountIn) private {
        token.safeTransferFrom(msg.sender, address(this), exactAmountIn);
        token.forceApprove(address(_permit2), exactAmountIn);
        _permit2.approve(address(token), address(_trustedRouter), exactAmountIn.toUint160(), type(uint48).max);
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
