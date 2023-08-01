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
    address[] senders;
    /// @notice The total number of nonzero deltas over all active + completed lockers
    uint128 nonzeroDeltaCount;
    /// @dev Represents the asset due/owed to each sender.
    /// Must all net to zero when the last sender is released.
    mapping(address => mapping(Asset => int256)) public assetDeltas;
    /// @notice
    mapping(Asset => uint256) public assetReserves;

    /**
     * @dev
     */
    modifier transient() {
        senders.push(msg.sender);

        // the caller does everything here, including paying what they owe via calls to settle
        _;

        if (senders.length == 1) {
            if (nonzeroDeltaCount != 0) revert CurrencyNotSettled();
            delete senders;
            delete nonzeroDeltaCount;
        } else {
            senders.pop();
        }
    }

    modifier withSender() {
        address sender = senders[senders.length - 1];
        if (msg.sender != sender) revert WrongSender(msg.sender, sender);
        _;
    }

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

    function settle(Asset asset) external payable withSender returns (uint256 paid) {
        uint256 reservesBefore = assetReserves[asset];
        assetReserves[asset] = asset.balanceOf();
        paid = assetReserves[asset] - reservesBefore;
        // subtraction must be safe
        _accountDelta(asset, -paid.toInt256());
    }

     function take(Asset asset, address to, uint256 amount) external withSender {
        _accountDelta(asset, amount.toInt256());
        assetReserves[currency] -= amount;
        asset.transfer(to, amount);
    }

    function mint(Currency currency, address to, uint256 amount) external withSender {
        _accountDelta(currency, amount.toInt128());
        _mint(to, currency.toId(), amount, "");
    }
    function burn(Currency currency, uint256 amount) internal {
        _burn(address(this), currency.toId(), amount);
        _accountDelta(currency, -(amount.toInt128()));
    }

    function _accountDelta(Asset asset, int256 delta) internal {
        if (delta == 0) return;

        address sender = senders[senders.length - 1];
        int256 current = assetDeltas[sender][asset];
        int256 next = current + delta;

        unchecked {
            if (next == 0) {
                nonzeroDeltaCount--;
            } else if (current == 0) {
                nonzeroDeltaCount++;
            }
        }

        assetDeltas[sender][asset] = next;
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
    function allowanceOfERC20(address poolToken, address owner, address spender) external view returns (uint256) {
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
    function isApprovedForAllERC721(address token, address owner, address operator) external view returns (bool) {
        return _isApprovedForAllERC721(token, owner, operator);
    }

    /// @inheritdoc IVault
    function approveERC721(address sender, address to, uint256 tokenId) external withRegisteredPool(msg.sender) {
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
                                          Swaps
    *******************************************************************************/

    /// @inheritdoc IVault
    function singleSwap(
        IVault.SingleSwap calldata params
    ) external payable transient nonReentrant whenNotPaused returns (uint256) {
        IERC20 tokenIn = params.assetIn.toIERC20(_weth);
        IERC20 tokenOut = params.assetOut.toIERC20(_weth);

        (uint256 amountCalculated, uint256 amountIn, uint256 amountOut) = swap(
            IVault.SwapParams({
                kind: params.kind,
                pool: params.pool,
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                amountGiven: params.amountGiven,
                limit: params.limit,
                deadline: params.deadline,
                userData: params.userData
            })
        );

        _receiveAsset(params.assetIn, amountIn, msg.sender);

        _sendAsset(params.assetOut, amountOut, payable(msg.sender));

        // If the asset in is ETH, then `amountIn` ETH was wrapped into WETH.
        _handleRemainingEth(params.assetIn.isETH() ? amountIn : 0);

        emit Swap(params.pool, tokenIn, tokenOut, amountIn, amountOut);

        return amountCalculated;
    }

    function swap(
        IVault.SwapParams memory params
    ) public withSender returns (uint256 amountCalculated, uint256 amountIn, uint256 amountOut) {
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

        //tokenInBalance = tokenInBalance + amountIn;
        //tokenOutBalance = tokenOutBalance - amountOut;

        if (params.kind == SwapKind.GIVEN_IN ? amountOut < params.limit : amountIn > params.limit) {
            revert SwapLimit(amountOut, params.limit);
        }

        // Because no tokens were registered or deregistered between now or when we retrieved the indexes for
        // 'token in' and 'token out', we can use `unchecked_setAt` to save storage reads.
        // poolBalances.unchecked_setAt(indexIn, tokenInBalance);
        // poolBalances.unchecked_setAt(indexOut, tokenOutBalance);

        // Credit amountIn of tokenIn
        _accountDelta(params.tokenIn.asAsset(), -int256(amountIn));
        // Debit amountOut of tokenOut
        _accountDelta(params.tokenOut.asAsset(), int256(amountOut));
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
    function getPoolTokens(
        address pool
    ) external view withRegisteredPool(pool) returns (IERC20[] memory tokens, uint256[] memory balances) {
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

        // The Vault ignores the `sender`: it is up to the Pool to keep track of
        // their participation.
        // We need to track how much of the received ETH was used and wrapped into WETH to return any excess.
        uint256 wrappedEth = 0;

        uint256[] memory finalBalances = new uint256[](balances.length);
        for (uint256 i = 0; i < assets.length; ++i) {
            uint256 amountIn = amountsIn[i];
            if (amountIn > maxAmountsIn[i]) {
                revert JoinAboveMax();
            }

            // Receive assets from the sender
            Asset asset = assets[i];
            _receiveAsset(asset, amountIn, msg.sender);

            if (asset.isETH()) {
                wrappedEth = wrappedEth + amountIn;
            }

            finalBalances[i] += amountIn;
        }

        // All that remains is storing the new Pool balances.
        _setPoolBalances(pool, finalBalances);

        // Handle any used and remaining ETH.
        _handleRemainingEth(wrappedEth);

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
            _sendAsset(assets[i], amountOut, payable(msg.sender));

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
    function _validateTokensAndGetBalances(
        address pool,
        IERC20[] memory expectedTokens
    ) private view returns (uint256[] memory) {
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

    /*******************************************************************************
                                    Utils
    *******************************************************************************/

    /**
     * @dev Returns excess ETH back to the contract caller, assuming `amountUsed` has been spent. Reverts
     * if the caller sent less ETH than `amountUsed`.
     *
     * Because the caller might not know exactly how much ETH a Vault action will require, they may send extra.
     * Note that this excess value is returned *to the contract caller* (msg.sender). If caller and e.g. swap sender are
     * not the same (because the caller is a relayer for the sender), then it is up to the caller to manage this
     * returned ETH.
     */
    function _handleRemainingEth(uint256 amountUsed) internal {
        if (msg.value < amountUsed) {
            revert InsufficientEth();
        }

        uint256 excess = msg.value - amountUsed;
        if (excess > 0) {
            payable(msg.sender).sendValue(excess);
        }
    }

    /**
     * @dev Receives `amount` of `asset` from `sender`. If `fromInternalBalance` is true, it first withdraws as much
     * as possible from Internal Balance, then transfers any remaining amount.
     *
     * If `asset` is ETH, `fromInternalBalance` must be false (as ETH cannot be held as internal balance), and the funds
     * will be wrapped into WETH.
     *
     * WARNING: this function does not check that the contract caller has actually supplied any ETH - it is up to the
     * caller of this function to check that this is true to prevent the Vault from using its own ETH (though the Vault
     * typically doesn't hold any).
     */
    function _receiveAsset(Asset asset, uint256 amount, address sender) internal {
        if (amount == 0) {
            return;
        }

        if (asset.isETH()) {
            // The ETH amount to receive is deposited into the WETH contract, which will in turn mint WETH for
            // the Vault at a 1:1 ratio.

            // A check for this condition is also introduced by the compiler, but this one provides a revert reason.
            // Note we're checking for the Vault's total balance, *not* ETH sent in this transaction.
            if (address(this).balance < amount) {
                revert InsufficientEth();
            }
            _weth.deposit{ value: amount }();
        } else {
            IERC20 token = asset.asIERC20();

            token.safeTransferFrom(sender, address(this), amount);
        }
    }

    /**
     * @dev Sends `amount` of `asset` to `recipient`. If `toInternalBalance` is true, the asset is deposited as Internal
     * Balance instead of being transferred.
     *
     * If `asset` is ETH, `toInternalBalance` must be false (as ETH cannot be held as internal balance), and the funds
     * are instead sent directly after unwrapping WETH.
     */
    function _sendAsset(Asset asset, uint256 amount, address payable recipient) internal {
        if (amount == 0) {
            return;
        }

        if (asset.isETH()) {
            // First, the Vault withdraws deposited ETH from the WETH contract, by burning the same amount of WETH
            // from the Vault. This receipt will be handled by the Vault's `receive`.
            _weth.withdraw(amount);

            // Then, the withdrawn ETH is sent to the recipient.
            recipient.sendValue(amount);
        } else {
            IERC20 token = asset.asIERC20();
            token.safeTransfer(recipient, amount);
        }
    }
}
