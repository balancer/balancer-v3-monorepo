// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";

import { ReentrancyGuard } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/ReentrancyGuard.sol";
import { TemporarilyPausable } from "@balancer-labs/v3-solidity-utils/contracts/helpers/TemporarilyPausable.sol";
import { Asset, AssetHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/AssetHelpers.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { EnumerableMap } from "@balancer-labs/v3-solidity-utils/contracts/openzeppelin/EnumerableMap.sol";

import { ERC20MultiToken } from "./ERC20MultiToken.sol";
import { ERC721MultiToken } from "./ERC721MultiToken.sol";
import { PoolRegistry } from "./PoolRegistry.sol";

contract Vault is IVault, ERC20MultiToken, ERC721MultiToken, PoolRegistry, ReentrancyGuard, TemporarilyPausable {
    using EnumerableMap for EnumerableMap.IERC20ToUint256Map;
    using InputHelpers for uint256;
    using AssetHelpers for address[];
    using ArrayHelpers for uint256[];

    // solhint-disable-next-line var-name-mixedcase
    IWETH private immutable _weth;

    constructor(
        IWETH weth,
        uint256 pauseWindowDuration,
        uint256 bufferPeriodDuration
    ) TemporarilyPausable(pauseWindowDuration, bufferPeriodDuration) {
        _weth = weth;
    }

    /*******************************************************************************
                              ERC20 Balancer Pool Tokens
    *******************************************************************************/

    /// @inheritdoc IVault
    function totalSupplyOfERC20(address poolToken) external view returns (uint256) {
        return _totalSupplyOfERC20(poolToken);
    }

    /// @inheritdoc IVault
    function balanceOfERC20(address poolToken, address account) external view returns (uint256) {
        return _balanceOfERC20(poolToken, account);
    }

    /// @inheritdoc IVault
    function allowanceOfERC20(
        address poolToken,
        address owner,
        address spender
    ) external view returns (uint256) {
        return _allowanceOfERC20(poolToken, owner, spender);
    }

    /// @inheritdoc IVault
    function transferERC20(
        address owner,
        address to,
        uint256 amount
    ) external withRegisteredPool(msg.sender) returns (bool) {
        _transferERC20(msg.sender, owner, to, amount);
        return true;
    }

    /// @inheritdoc IVault
    function approveERC20(
        address sender,
        address spender,
        uint256 amount
    ) external withRegisteredPool(msg.sender) returns (bool) {
        _approveERC20(msg.sender, sender, spender, amount);
        return true;
    }

    /// @inheritdoc IVault
    function transferFromERC20(
        address spender,
        address from,
        address to,
        uint256 amount
    ) external withRegisteredPool(msg.sender) returns (bool) {
        _spendAllowance(msg.sender, from, spender, amount);
        _transferERC20(msg.sender, from, to, amount);
        return true;
    }

    /*******************************************************************************
                            ERC721 Balancer Pool Tokens
    *******************************************************************************/

    /// @inheritdoc IVault
    function balanceOfERC721(address token, address owner) external view returns (uint256) {
        return _balanceOfERC721(token, owner);
    }

    /// @inheritdoc IVault
    function ownerOfERC721(address token, uint256 tokenId) external view returns (address) {
        return _safeOwnerOfERC721(token, tokenId);
    }

    /// @inheritdoc IVault
    function getApprovedERC721(address token, uint256 tokenId) external view returns (address) {
        return _getApprovedERC721(token, tokenId);
    }

    /// @inheritdoc IVault
    function isApprovedForAllERC721(
        address token,
        address owner,
        address operator
    ) external view returns (bool) {
        return _isApprovedForAllERC721(token, owner, operator);
    }

    /// @inheritdoc IVault
    function approveERC721(
        address sender,
        address to,
        uint256 tokenId
    ) external withRegisteredPool(msg.sender) {
        _approveERC721(msg.sender, sender, to, tokenId);
    }

    /// @inheritdoc IVault
    function setApprovalForAllERC721(
        address sender,
        address operator,
        bool approved
    ) external withRegisteredPool(msg.sender) {
        _setApprovalForAllERC721(msg.sender, sender, operator, approved);
    }

    /// @inheritdoc IVault
    function transferFromERC721(
        address sender,
        address from,
        address to,
        uint256 tokenId
    ) public withRegisteredPool(msg.sender) {
        _transferFromERC721(msg.sender, sender, from, to, tokenId);
    }

    /// @inheritdoc IVault
    function safeTransferFromERC721(
        address sender,
        address from,
        address to,
        uint256 tokenId
    ) external withRegisteredPool(msg.sender) {
        _safeTransferFromERC721(msg.sender, sender, from, to, tokenId);
    }

    /// @inheritdoc IVault
    function safeTransferFromERC721(
        address sender,
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) external withRegisteredPool(msg.sender) {
        _safeTransferFromERC721(msg.sender, sender, from, to, tokenId, data);
    }

    /*******************************************************************************
                                    Pool Registration
    *******************************************************************************/

    /// @inheritdoc IVault
    function registerPool(address factory, IERC20[] memory tokens) external nonReentrant whenNotPaused {
        _registerPool(factory, tokens);
    }

    /// @inheritdoc IVault
    function isRegisteredPool(address pool) external view returns (bool) {
        return _isRegisteredPool(pool);
    }

    /// @inheritdoc IVault
    function getPoolTokens(address pool)
        external
        view
        withRegisteredPool(pool)
        returns (IERC20[] memory tokens, uint256[] memory balances)
    {
        return _getPoolTokens(pool);
    }

    /// @inheritdoc IVault
    function WETH() public view returns (IWETH) {
        // solhint-disable-previous-line func-name-mixedcase
        return _weth;
    }

    /*******************************************************************************
                                    Pools
    *******************************************************************************/

    /**
     * @dev Sets the balances of a Pool's tokens to `balances`.
     *
     * WARNING: this assumes `balances` has the same length and order as the Pool's tokens.
     */
    function _setPoolBalances(address pool, uint256[] memory balances) internal {
        EnumerableMap.IERC20ToUint256Map storage poolBalances = _poolTokenBalances[pool];

        for (uint256 i = 0; i < balances.length; ++i) {
            // Since we assume all balances are properly ordered, we can simply use `unchecked_setAt` to avoid one less
            // storage read per token.
            poolBalances.unchecked_setAt(i, balances[i]);
        }
    }

    /**
     * @dev Returns the total balances for `pool`'s `expectedTokens`.
     *
     * `expectedTokens` must exactly equal the token array returned by `getPoolTokens`: both arrays must have the same
     * length, elements and order. Additionally, the Pool must have at least one registered token.
     */
    function _validateTokensAndGetBalances(address pool, IERC20[] memory expectedTokens)
        private
        view
        returns (bytes32[] memory)
    {
        (IERC20[] memory actualTokens, bytes32[] memory balances) = _getPoolTokens(pool);
        actualTokens.length.ensureInputLengthMatch(expectedTokens.length);
        if (actualTokens.length == 0) {
            revert PoolHasNoTokens(pool);
        }

        for (uint256 i = 0; i < actualTokens.length; ++i) {
            if (actualTokens[i] != expectedTokens[i]) {
                revert TokensMismatch(actualTokens[i], expectedTokens[i]);
            }
        }

        return balances;
    }

    function joinPool(
        bytes32 pool,
        address sender,
        address recipient,
        JoinPoolRequest memory request
    ) external payable whenNotPaused nonReentrant withRegisteredPool(pool) {
        request.assets.ensureInputLengthMatch(request.limits.length);

        // We first check that the caller passed the Pool's registered tokens in the correct order
        // and retrieve the current balance for each.
        IERC20[] memory tokens = request.assets.toIERC20();
        bytes32[] memory balances = _validateTokensAndGetBalances(pool, tokens);

        // The bulk of the work is done here: the corresponding Pool hook is called
        // its final balances are computed, assets are transferred, and fees are paid.
        (uint256[] memory totalBalances, uint256 lastChangeBlock) = balances.totalsAndLastChangeBlock();

        (amountsInOrOut, dueProtocolFeeAmounts) = pool.onJoinPool(
            pool,
            sender,
            recipient,
            totalBalances,
            lastChangeBlock,
            _getProtocolSwapFeePercentage(),
            change.userData
        );

        balances.length.ensureInputLengthMatch(amountsInOrOut.length, dueProtocolFeeAmounts.length);

        // The Vault ignores the `recipient` in joins and the `sender` in exits: it is up to the Pool to keep track of
        // their participation.
        finalBalances = _processJoinPoolTransfers(sender, change, balances, amountsInOrOut, dueProtocolFeeAmounts);

        // All that remains is storing the new Pool balances.
        _setPoolBalances(pool, finalBalances);

        emit PoolBalanceChanged(
            pool,
            sender,
            tokens,
            // We can unsafely cast to int256 because balances are actually stored as uint112
            _unsafeCastToInt256(amountsInOrOut, true),
            paidProtocolSwapFeeAmounts
        );
    }
}
