// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

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

import "forge-std/Test.sol";

contract Vault is IVault, ERC20MultiToken, ERC721MultiToken, PoolRegistry, ReentrancyGuard, TemporarilyPausable {
    using EnumerableMap for EnumerableMap.IERC20ToUint256Map;
    using InputHelpers for uint256;
    using AssetHelpers for *;
    using ArrayHelpers for uint256[];
    using Address for address payable;
    using SafeERC20 for IERC20;
    using SafeCast for *;

    // solhint-disable-next-line var-name-mixedcase
    IWETH private immutable _weth;

    /// @notice
    address[] private _handlers;
    /// @notice The total number of nonzero deltas over all active + completed lockers
    uint128 private _nonzeroDeltaCount;
    /// @dev Represents the asset due/owed to each handler.
    /// Must all net to zero when the last handler is released.
    mapping(address => mapping(Asset => int256)) private _assetDeltas;
    /// @notice
    mapping(Asset => uint256) private _assetReserves;

    constructor(
        IWETH weth,
        uint256 pauseWindowDuration,
        uint256 bufferPeriodDuration
    ) TemporarilyPausable(pauseWindowDuration, bufferPeriodDuration) {
        _weth = weth;
    }

    /*******************************************************************************
                              Transient Accounting
    *******************************************************************************/

    /**
     * @dev
     */
    modifier transient() {
        _handlers.push(msg.sender);

        // the caller does everything here, including paying what they owe via calls to settle
        _;

        if (_handlers.length == 1) {
            if (_nonzeroDeltaCount != 0) revert BalanceNotSettled();
            delete _handlers;
            delete _nonzeroDeltaCount;
        } else {
            _handlers.pop();
        }
    }

    /**
     * @dev
     */
    modifier withHandler() {
        address handler = _handlers[_handlers.length - 1];
        if (msg.sender != handler) revert WrongSender(msg.sender, handler);
        _;
    }

    function settle(Asset asset) public payable withHandler returns (uint256 paid) {
        uint256 reservesBefore = _assetReserves[asset];
        _assetReserves[asset] = asset.balanceOf();
        paid = _assetReserves[asset] - reservesBefore;
        // subtraction must be safe
        _accountDelta(asset, -paid.toInt256());
    }

    function send(
        Asset asset,
        address to,
        uint256 amount
    ) public withHandler {
        // effects
        _accountDelta(asset, amount.toInt256());
        _assetReserves[asset] -= amount;
        // interactions
        asset.send(to, amount, _weth);
    }

    function mint(
        Asset asset,
        address to,
        uint256 amount
    ) public withHandler {
        _accountDelta(asset, amount.toInt256());
        _mintERC20(asset.asAddress(), to, amount);
    }

    function retrieve(
        Asset asset,
        address from,
        uint256 amount
    ) public withHandler {
        // effects
        _accountDelta(asset, -(amount.toInt256()));
        _assetReserves[asset] += amount;
        // interactions
        asset.retrieve(from, amount, _weth);
    }

    function burn(Asset asset, uint256 amount) public withHandler {
        _burnERC20(asset.asAddress(), msg.sender, amount);
        _accountDelta(asset, -(amount.toInt256()));
    }

    function getHandler() internal view returns (address) {
        return _handlers[_handlers.length - 1];
    }

    /**
     * @dev Accounts the delta for the current handler and asset.
     * Positive delta represents debt, while negative delta represents delta surplus.
     */
    function _accountDelta(Asset asset, int256 delta) internal {
        if (delta == 0) return;

        address handler = _handlers[_handlers.length - 1];
        int256 current = _assetDeltas[handler][asset];
        int256 next = current + delta;

        unchecked {
            if (next == 0) {
                _nonzeroDeltaCount--;
            } else if (current == 0) {
                _nonzeroDeltaCount++;
            }
        }

        _assetDeltas[handler][asset] = next;
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
        address handler,
        address spender,
        uint256 amount
    ) external withRegisteredPool(msg.sender) returns (bool) {
        _approveERC20(msg.sender, handler, spender, amount);
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
                                          Swaps
    *******************************************************************************/

    function swap(IVault.SwapParams memory params)
        public
        whenNotPaused
        withHandler
        returns (
            uint256 amountCalculated,
            uint256 amountIn,
            uint256 amountOut
        )
    {
        // The deadline is timestamp-based: it should not be relied upon for sub-minute accuracy.
        // solhint-disable-next-line not-rely-on-time
        if (block.timestamp > params.deadline) {
            revert SwapDeadline();
        }

        if (params.amountGiven == 0) {
            revert AmountInZero();
        }

        if (params.tokenIn == params.tokenOut) {
            revert CannotSwapSameToken();
        }

        // We access both token indexes without checking existence, because we will do it manually immediately after.
        EnumerableMap.IERC20ToUint256Map storage poolBalances = _poolTokenBalances[params.pool];
        uint256 indexIn = poolBalances.unchecked_indexOf(params.tokenIn);
        uint256 indexOut = poolBalances.unchecked_indexOf(params.tokenOut);

        if (indexIn == 0 || indexOut == 0) {
            // The tokens might not be registered because the Pool itself is not registered. We check this to provide a
            // more accurate revert reason.
            _ensureRegisteredPool(params.pool);
            revert TokenNotRegistered();
        }

        // EnumerableMap stores indices *plus one* to use the zero index as a sentinel value - because these are valid,
        // we can undo this.
        indexIn -= 1;
        indexOut -= 1;

        uint256 tokenInBalance;
        uint256 tokenOutBalance;

        uint256[] memory currentBalances = new uint256[](poolBalances.length());

        for (uint256 i = 0; i < poolBalances.length(); i++) {
            // Because the iteration is bounded by `tokenAmount`, and no tokens are registered or deregistered here, we
            // know `i` is a valid token index and can use `unchecked_valueAt` to save storage reads.
            uint256 balance = poolBalances.unchecked_valueAt(i);

            currentBalances[i] = balance;

            if (i == indexIn) {
                tokenInBalance = balance;
            } else if (i == indexOut) {
                tokenOutBalance = balance;
            }
        }

        // Perform the swap request callback and compute the new balances for 'token in' and 'token out' after the swap
        amountCalculated = IBasePool(params.pool).onSwap(
            IBasePool.SwapParams({
                kind: params.kind,
                tokenIn: params.tokenIn,
                tokenOut: params.tokenOut,
                amountGiven: params.amountGiven,
                balances: currentBalances,
                indexIn: indexIn,
                indexOut: indexOut,
                sender: msg.sender,
                userData: params.userData
            })
        );

        (amountIn, amountOut) = params.kind == SwapKind.GIVEN_IN
            ? (params.amountGiven, amountCalculated)
            : (amountCalculated, params.amountGiven);

        tokenInBalance = tokenInBalance + amountIn;
        tokenOutBalance = tokenOutBalance - amountOut;

        // Because no tokens were registered or deregistered between now or when we retrieved the indexes for
        // 'token in' and 'token out', we can use `unchecked_setAt` to save storage reads.
        poolBalances.unchecked_setAt(indexIn, tokenInBalance);
        poolBalances.unchecked_setAt(indexOut, tokenOutBalance);

        if (params.kind == SwapKind.GIVEN_IN ? amountOut < params.limit : amountIn > params.limit) {
            revert SwapLimit(amountOut, params.limit);
        }

        // Account amountIn of tokenIn
        _accountDelta(params.tokenIn.asAsset(), int256(amountIn));
        // Account amountOut of tokenOut
        _accountDelta(params.tokenOut.asAsset(), -int256(amountOut));
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

    /// @inheritdoc IVault
    function addLiquidity(
        address pool,
        Asset[] memory assets,
        uint256[] memory maxAmountsIn,
        uint256 minBptAmountOut,
        bytes memory userData
    )
        external
        payable
        transient
        whenNotPaused
        nonReentrant
        withRegisteredPool(pool)
        returns (uint256[] memory amountsIn, uint256 bptAmountOut)
    {
        InputHelpers.ensureInputLengthMatch(assets.length, maxAmountsIn.length);

        // We first check that the caller passed the Pool's registered tokens in the correct order
        // and retrieve the current balance for each.
        IERC20[] memory tokens = assets.toIERC20(_weth);
        uint256[] memory balances = _validateTokensAndGetBalances(pool, tokens);

        // The bulk of the work is done here: the corresponding Pool hook is called
        // its final balances are computed, assets are transferred, and fees are paid.
        (amountsIn, bptAmountOut) = IBasePool(pool).onAddLiquidity(msg.sender, balances, maxAmountsIn, userData);

        if (bptAmountOut < minBptAmountOut) {
            revert BtpAmountBelowMin();
        }

        // The Vault ignores the `handler`: it is up to the Pool to keep track of
        // their participation.
        // We need to track how much of the received ETH was used and wrapped into WETH to return any excess.
        uint256 wrappedEth = 0;

        uint256[] memory finalBalances = new uint256[](balances.length);
        for (uint256 i = 0; i < assets.length; ++i) {
            uint256 amountIn = amountsIn[i];
            if (amountIn > maxAmountsIn[i]) {
                revert JoinAboveMax();
            }

            // Receive assets from the handler
            Asset asset = assets[i];
            _accountDelta(asset, int256(amountIn));
            retrieve(asset, msg.sender, amountIn);
            settle(asset);

            if (asset.isETH()) {
                wrappedEth = wrappedEth + amountIn;
            }

            finalBalances[i] += amountIn;
        }

        // All that remains is storing the new Pool balances.
        _setPoolBalances(pool, finalBalances);

        // Handle any used and remaining ETH.
        address(this).returnEth(wrappedEth);

        _mintERC20(pool, msg.sender, bptAmountOut);

        emit PoolBalanceChanged(pool, msg.sender, tokens, amountsIn.unsafeCastToInt256(true));
    }

    /// @inheritdoc IVault
    function removeLiquidity(
        address pool,
        Asset[] memory assets,
        uint256[] memory minAmountsOut,
        uint256 bptAmountIn,
        bytes memory userData
    ) external whenNotPaused nonReentrant withRegisteredPool(pool) returns (uint256[] memory amountsOut) {
        InputHelpers.ensureInputLengthMatch(assets.length, minAmountsOut.length);

        // We first check that the caller passed the Pool's registered tokens in the correct order, and retrieve the
        // current balance for each.
        IERC20[] memory tokens = assets.toIERC20(_weth);
        uint256[] memory balances = _validateTokensAndGetBalances(pool, tokens);

        // The bulk of the work is done here: the corresponding Pool hook is called, its final balances are computed,
        // assets are transferred, and fees are paid.
        amountsOut = IBasePool(pool).onRemoveLiquidity(msg.sender, balances, minAmountsOut, bptAmountIn, userData);

        uint256[] memory finalBalances = new uint256[](balances.length);
        for (uint256 i = 0; i < assets.length; ++i) {
            uint256 amountOut = amountsOut[i];
            if (amountOut < minAmountsOut[i]) {
                revert ExitBelowMin();
            }

            // Send tokens to the recipient
            assets[i].send(msg.sender, amountOut, _weth);

            // Compute the new Pool balances. A Pool's token balance always decreases after an exit (potentially by 0).
            finalBalances[i] = balances[i] - amountOut;
        }

        // All that remains is storing the new Pool balances.
        _setPoolBalances(pool, finalBalances);

        _burnERC20(pool, msg.sender, bptAmountIn);

        emit PoolBalanceChanged(
            pool,
            msg.sender,
            tokens,
            // We can unsafely cast to int256 because balances are actually stored as uint112
            amountsOut.unsafeCastToInt256(false)
        );
    }

    /**
     * @dev Sets the balances of a Pool's tokens to `newBalances`.
     *
     * WARNING: this assumes `newBalances` has the same length and order as the Pool's tokens.
     */
    function _setPoolBalances(address pool, uint256[] memory newBalances) internal {
        EnumerableMap.IERC20ToUint256Map storage poolBalances = _poolTokenBalances[pool];

        for (uint256 i = 0; i < newBalances.length; ++i) {
            // Since we assume all newBalances are properly ordered, we can simply use `unchecked_setAt`
            // to avoid one less storage read per token.
            poolBalances.unchecked_setAt(i, newBalances[i]);
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
        returns (uint256[] memory)
    {
        (IERC20[] memory actualTokens, uint256[] memory balances) = _getPoolTokens(pool);
        InputHelpers.ensureInputLengthMatch(actualTokens.length, expectedTokens.length);
        if (actualTokens.length == 0) {
            revert PoolHasNoTokens(pool);
        }

        for (uint256 i = 0; i < actualTokens.length; ++i) {
            if (actualTokens[i] != expectedTokens[i]) {
                revert TokensMismatch(address(actualTokens[i]), address(expectedTokens[i]));
            }
        }

        return balances;
    }
}
