// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";

import { IRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IRouter.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";
import { WeightedPoolFactory } from "@balancer-labs/v3-pool-weighted/contracts/WeightedPoolFactory.sol";
import {
    TokenConfig,
    PoolRoleAccounts,
    LiquidityManagement
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { SwapFeeMinimizer } from "./SwapFeeMinimizer.sol";

struct PoolCreationParams {
    string name;
    string symbol;
    TokenConfig[] tokens;
    uint256[] normalizedWeights;
    uint256 swapFeePercentage;
    address poolHooksContract;
    bool enableDonation;
    bool disableUnbalancedLiquidity;
}

struct MinimizerParams {
    IERC20[] inputTokens;
    IERC20 outputToken;
    address initialOwner;
    uint256 minimalFee;
}

contract SwapFeeMinimizerFactory {
    IRouter public immutable router;
    IVault public immutable vault;
    IPermit2 public immutable permit2;

    mapping(address => SwapFeeMinimizer) public feeMinimizers;
    address private _pendingPool;

    event SwapFeeMinimizerDeployed(
        address indexed pool,
        IERC20 indexed outputToken,
        address indexed initialOwner,
        SwapFeeMinimizer minimizer,
        uint256 minimalFee
    );

    error NoPendingPool();

    constructor(IRouter _router, IVault _vault, IPermit2 _permit2) {
        router = _router;
        vault = _vault;
        permit2 = _permit2;
    }

    function deployWeightedPoolWithMinimizer(
        PoolCreationParams memory poolParams,
        MinimizerParams memory minimizerParams,
        WeightedPoolFactory poolFactory,
        bytes32 salt
    ) external returns (address pool, SwapFeeMinimizer minimizer) {
        address predictedMinimizer = _predictMinimizerAddress(
            minimizerParams.inputTokens,
            minimizerParams.outputToken,
            minimizerParams.minimalFee,
            minimizerParams.initialOwner,
            salt
        );

        pool = _deployPool(poolFactory, poolParams, predictedMinimizer, salt);

        _pendingPool = pool;
        
        minimizer = _deployMinimizer(
            minimizerParams.inputTokens,
            minimizerParams.outputToken,
            minimizerParams.minimalFee,
            minimizerParams.initialOwner,
            salt
        );

        feeMinimizers[pool] = minimizer;
        _pendingPool = address(0);

        emit SwapFeeMinimizerDeployed(pool, minimizerParams.outputToken, minimizerParams.initialOwner, minimizer, minimizerParams.minimalFee);
    }

    function _deployPool(
        WeightedPoolFactory poolFactory,
        PoolCreationParams memory poolParams,
        address swapFeeManager,
        bytes32 salt
    ) internal returns (address) {
        PoolRoleAccounts memory roleAccounts = PoolRoleAccounts({
            pauseManager: address(0),
            swapFeeManager: swapFeeManager,
            poolCreator: address(0)
        });

        return poolFactory.create(
            poolParams.name,
            poolParams.symbol,
            poolParams.tokens,
            poolParams.normalizedWeights,
            roleAccounts,
            poolParams.swapFeePercentage,
            poolParams.poolHooksContract,
            poolParams.enableDonation,
            poolParams.disableUnbalancedLiquidity,
            salt
        );
    }

    function getCurrentPool() external view returns (address) {
        if (_pendingPool == address(0)) {
            revert NoPendingPool();
        }
        return _pendingPool;
    }

    function _predictMinimizerAddress(
        IERC20[] memory inputTokens,
        IERC20 outputToken,
        uint256 minimalFee,
        address initialOwner,
        bytes32 salt
    ) internal view returns (address) {
        bytes memory constructorArgs = abi.encode(
            router,
            vault,
            permit2,
            inputTokens,
            outputToken,
            minimalFee,
            initialOwner
        );
        
        bytes memory creationCode = abi.encodePacked(
            type(SwapFeeMinimizer).creationCode,
            constructorArgs
        );

        return Create2.computeAddress(salt, keccak256(creationCode), address(this));
    }

    function _deployMinimizer(
        IERC20[] memory inputTokens,
        IERC20 outputToken,
        uint256 minimalFee,
        address initialOwner,
        bytes32 salt
    ) internal returns (SwapFeeMinimizer) {
        bytes memory constructorArgs = abi.encode(
            router,
            vault,
            permit2,
            inputTokens,
            outputToken,
            minimalFee,
            initialOwner
        );

        bytes memory creationCode = abi.encodePacked(
            type(SwapFeeMinimizer).creationCode,
            constructorArgs
        );

        address minimizerAddress = Create2.deploy(0, salt, creationCode);
        return SwapFeeMinimizer(minimizerAddress);
    }

    function getMinimizerForPool(address pool) external view returns (SwapFeeMinimizer) {
        return feeMinimizers[pool];
    }
}