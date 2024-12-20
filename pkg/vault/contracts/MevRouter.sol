// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";

import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import { IMevRouter } from "@balancer-labs/v3-interfaces/contracts/vault/IMevRouter.sol";
import { IMevTaxCollector } from "@balancer-labs/v3-interfaces/contracts/vault/IMevTaxCollector.sol";
import { IRouterSwap } from "@balancer-labs/v3-interfaces/contracts/vault/IMevRouter.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { SwapKind } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { SingletonAuthentication } from "./SingletonAuthentication.sol";
import { RouterSwap } from "./RouterSwap.sol";

contract MevRouter is IMevRouter, SingletonAuthentication, RouterSwap {
    IMevTaxCollector internal _mevTaxCollector;

    uint256 internal _mevTaxMultiplier;
    uint256 internal _priorityGasThreshold;

    bool private _isMevTaxEnabled;

    constructor(
        IVault vault,
        IWETH weth,
        IPermit2 permit2,
        string memory routerVersion,
        MevRouterParams memory params
    ) SingletonAuthentication(vault) RouterSwap(vault, weth, permit2, routerVersion) {
        _mevTaxCollector = params.mevTaxCollector;
        _mevTaxMultiplier = params.mevTaxMultiplier;
        _priorityGasThreshold = params.priorityGasThreshold;
        _isMevTaxEnabled = true;
    }

    /// @inheritdoc IMevRouter
    function isMevTaxEnabled() external view returns (bool) {
        return _isMevTaxEnabled;
    }

    /// @inheritdoc IMevRouter
    function enableMevTax() external authenticate {
        _isMevTaxEnabled = true;
    }

    /// @inheritdoc IMevRouter
    function disableMevTax() external authenticate {
        _isMevTaxEnabled = false;
    }

    /// @inheritdoc IMevRouter
    function getMevTaxCollector() external view returns (IMevTaxCollector) {
        return _mevTaxCollector;
    }

    /// @inheritdoc IMevRouter
    function setMevTaxCollector(IMevTaxCollector newMevTaxCollector) external authenticate {
        _mevTaxCollector = newMevTaxCollector;
    }

    /// @inheritdoc IMevRouter
    function getMevTaxMultiplier() external view returns (uint256) {
        return _mevTaxMultiplier;
    }

    /// @inheritdoc IMevRouter
    function setMevTaxMultiplier(uint256 newMevTaxMultiplier) external authenticate {
        _mevTaxMultiplier = newMevTaxMultiplier;
    }

    /// @inheritdoc IMevRouter
    function getPriorityGasThreshold() external view returns (uint256) {
        return _priorityGasThreshold;
    }

    /// @inheritdoc IMevRouter
    function setPriorityGasThreshold(uint256 newPriorityGasThreshold) external authenticate {
        _priorityGasThreshold = newPriorityGasThreshold;
    }

    /// @inheritdoc IRouterSwap
    function swapSingleTokenExactIn(
        address pool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 exactAmountIn,
        uint256 minAmountOut,
        uint256 deadline,
        bool wethIsEth,
        bytes calldata userData
    ) external payable override(RouterSwap, IRouterSwap) saveSender(msg.sender) returns (uint256) {
        _chargeMevTax(pool);

        return
            abi.decode(
                _vault.unlock(
                    abi.encodeCall(
                        RouterSwap.swapSingleTokenHook,
                        SwapSingleTokenHookParams({
                            sender: msg.sender,
                            kind: SwapKind.EXACT_IN,
                            pool: pool,
                            tokenIn: tokenIn,
                            tokenOut: tokenOut,
                            amountGiven: exactAmountIn,
                            limit: minAmountOut,
                            deadline: deadline,
                            wethIsEth: wethIsEth,
                            userData: userData
                        })
                    )
                ),
                (uint256)
            );
    }

    /// @inheritdoc IRouterSwap
    function swapSingleTokenExactOut(
        address pool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 exactAmountOut,
        uint256 maxAmountIn,
        uint256 deadline,
        bool wethIsEth,
        bytes calldata userData
    ) external payable override(RouterSwap, IRouterSwap) saveSender(msg.sender) returns (uint256) {
        _chargeMevTax(pool);

        return
            abi.decode(
                _vault.unlock(
                    abi.encodeCall(
                        RouterSwap.swapSingleTokenHook,
                        SwapSingleTokenHookParams({
                            sender: msg.sender,
                            kind: SwapKind.EXACT_OUT,
                            pool: pool,
                            tokenIn: tokenIn,
                            tokenOut: tokenOut,
                            amountGiven: exactAmountOut,
                            limit: maxAmountIn,
                            deadline: deadline,
                            wethIsEth: wethIsEth,
                            userData: userData
                        })
                    )
                ),
                (uint256)
            );
    }

    function _chargeMevTax(address pool) internal {
        if (_isMevTaxEnabled == false) {
            return;
        }

        uint256 priorityGasPrice = tx.gasprice - block.basefee;

        if (priorityGasPrice < _priorityGasThreshold) {
            return;
        }

        uint256 mevTax = priorityGasPrice * _mevTaxMultiplier;
        _mevTaxCollector.chargeMevTax{ value: mevTax }(pool);

        emit MevTaxCharged(pool, mevTax);
    }
}
