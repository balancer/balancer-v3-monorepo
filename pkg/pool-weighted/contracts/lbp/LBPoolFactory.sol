// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";

import { IPoolVersion } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/helpers/IPoolVersion.sol";
import { IRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IRouter.sol";
import { TokenConfig, PoolRoleAccounts } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { BasePoolFactory } from "@balancer-labs/v3-pool-utils/contracts/BasePoolFactory.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { Version } from "@balancer-labs/v3-solidity-utils/contracts/helpers/Version.sol";
import {
    ReentrancyGuardTransient
} from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/ReentrancyGuardTransient.sol";

import { WeightedPool } from "../WeightedPool.sol";
import { LBPool } from "./LBPool.sol";

/**
 * @notice LBPool Factory.
 * @dev This is a factory specific to LBPools, allowing only 2 tokens.
 */
contract LBPoolFactory is IPoolVersion, ReentrancyGuardTransient, BasePoolFactory, Version {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    // LBPs are constrained to two tokens.
    uint256 private constant _NUM_TOKENS = 2;

    string private _poolVersion;

    address internal immutable _trustedRouter;
    IPermit2 internal immutable _permit2;

    constructor(
        IVault vault,
        uint32 pauseWindowDuration,
        string memory factoryVersion,
        string memory poolVersion,
        address trustedRouter,
        IPermit2 permit2
    ) BasePoolFactory(vault, pauseWindowDuration, type(LBPool).creationCode) Version(factoryVersion) {
        _poolVersion = poolVersion;

        // LBPools are deployed with a router known to reliably report the originating address on operations.
        _trustedRouter = trustedRouter;
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
     * @param tokenConfig An array of descriptors for the tokens the pool will manage
     * @param normalizedWeights The pool weights (must add to FixedPoint.ONE)
     * @param swapFeePercentage Initial swap fee percentage
     * @param owner The owner address for pool; sole LP with swapEnable/swapFee change permissions
     * @param salt The salt value that will be passed to create3 deployment
     */
    function create(
        string memory name,
        string memory symbol,
        TokenConfig[] memory tokenConfig,
        uint256[] memory normalizedWeights,
        uint256 swapFeePercentage,
        address owner,
        bool swapEnabledOnStart,
        bytes32 salt
    ) external nonReentrant returns (address pool) {
        return
            _create(name, symbol, tokenConfig, normalizedWeights, swapFeePercentage, owner, swapEnabledOnStart, salt);
    }

    /**
     * @notice Deploys a new `LBPool` and seeds it with initial liquidity in the same tx.
     * @dev Tokens must be sorted for pool registration.
     * Use this method in case pool initialization frontrunning is an issue.
     * If the owner is the only address with liquidity of one of the tokens, this should not be necessary.
     * This method does not support native ETH management; WETH needs to be used instead.
     * @param name The name of the pool
     * @param symbol The symbol of the pool
     * @param tokenConfig An array of descriptors for the tokenConfig the pool will manage
     * @param normalizedWeights The pool weights (must add to FixedPoint.ONE)
     * @param swapFeePercentage Initial swap fee percentage
     * @param owner The owner address for pool; sole LP with swapEnable/swapFee change permissions
     * @param salt The salt value that will be passed to create3 deployment
     * @param exactAmountsIn Token amounts in, matching token order
     */
    function createAndInitialize(
        string memory name,
        string memory symbol,
        TokenConfig[] memory tokenConfig,
        uint256[] memory normalizedWeights,
        uint256 swapFeePercentage,
        address owner,
        bool swapEnabledOnStart,
        bytes32 salt,
        uint256[] memory exactAmountsIn
    ) external nonReentrant returns (address pool) {
        // `create` checks token config length already
        pool = _create(
            name,
            symbol,
            tokenConfig,
            normalizedWeights,
            swapFeePercentage,
            owner,
            swapEnabledOnStart,
            salt
        );

        IERC20[] memory tokens = new IERC20[](_NUM_TOKENS);
        for (uint256 i = 0; i < _NUM_TOKENS; ++i) {
            tokens[i] = tokenConfig[i].token;

            // Pull necessary tokens and approve permit2 to use them via the router
            tokens[i].safeTransferFrom(msg.sender, address(this), exactAmountsIn[i]);
            tokens[i].forceApprove(address(_permit2), exactAmountsIn[i]);
            _permit2.approve(
                address(tokens[i]),
                address(_trustedRouter),
                exactAmountsIn[i].toUint160(),
                type(uint48).max
            );
        }

        IRouter(_trustedRouter).initialize(pool, tokens, exactAmountsIn, 0, false, "");
    }

    function _create(
        string memory name,
        string memory symbol,
        TokenConfig[] memory tokenConfig,
        uint256[] memory normalizedWeights,
        uint256 swapFeePercentage,
        address owner,
        bool swapEnabledOnStart,
        bytes32 salt
    ) internal returns (address pool) {
        InputHelpers.ensureInputLengthMatch(_NUM_TOKENS, tokenConfig.length);
        InputHelpers.ensureInputLengthMatch(_NUM_TOKENS, normalizedWeights.length);

        PoolRoleAccounts memory roleAccounts;
        // It's not necessary to set the pauseManager, as the owner can already effectively pause the pool by disabling
        // swaps. There is also no poolCreator, as the owner is already using this to earn revenue directly.
        roleAccounts.swapFeeManager = owner;

        pool = _create(
            abi.encode(
                WeightedPool.NewPoolParams({
                    name: name,
                    symbol: symbol,
                    numTokens: tokenConfig.length,
                    normalizedWeights: normalizedWeights,
                    version: _poolVersion
                }),
                getVault(),
                owner,
                swapEnabledOnStart,
                _trustedRouter
            ),
            salt
        );

        _registerPoolWithVault(
            pool,
            tokenConfig,
            swapFeePercentage,
            false, // protocol fee exempt
            roleAccounts,
            pool, // register the pool itself as the hook contract
            getDefaultLiquidityManagement()
        );
    }
}
