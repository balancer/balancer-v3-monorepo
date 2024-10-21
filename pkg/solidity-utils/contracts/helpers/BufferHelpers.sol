// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { PackedTokenBalance } from "./PackedTokenBalance.sol";

library BufferHelpers {
    using PackedTokenBalance for bytes32;
    using SafeCast for *;

    /**
     * @notice Returns the imbalance of a buffer in terms of the underlying asset.
     * @dev The imbalance refers to the difference between the buffer's underlying asset balance and its wrapped asset
     * balance, both expressed in terms of the underlying asset. A positive imbalance means the buffer holds more
     * underlying assets than wrapped assets, indicating that the excess underlying should be wrapped to restore
     * balance. Conversely, a negative imbalance means the buffer has more wrapped assets than underlying assets, so
     * during a wrap operation, fewer underlying tokens need to be wrapped, and the surplus wrapped tokens can be
     * returned to the caller.
     * For instance, consider the following scenario:
     * - buffer balances: 2 wrapped and 10 underlying
     * - wrapped rate: 2
     * - normalized buffer balances: 4 wrapped as underlying (2 wrapped * rate) and 10 underlying
     * - underlying token imbalance = (10 - 4) / 2 = 3 underlying
     * We need to wrap 3 underlying tokens to rebalance the buffer.
     * - 3 underlying = 1.5 wrapped
     * - final balances: 3.5 wrapped (2 existing + 1.5 new) and 7 underlying (10 existing - 3)
     * These balances are equal value, given the rate.
     */
    function getBufferUnderlyingImbalance(bytes32 bufferBalance, IERC4626 wrappedToken) internal view returns (int256) {
        int256 underlyingBalance = bufferBalance.getBalanceRaw().toInt256();

        int256 wrappedBalanceAsUnderlying = 0;
        if (bufferBalance.getBalanceDerived() > 0) {
            // The buffer underlying imbalance is used when wrapping (it means, deposit underlying and get wrapped
            // tokens), so we use `previewMint` to convert wrapped balance to underlying. The `mint` function is used
            // here, as it performs the inverse of a `deposit` operation.
            wrappedBalanceAsUnderlying = wrappedToken.previewMint(bufferBalance.getBalanceDerived()).toInt256();
        }

        // The return value may be positive (excess of underlying) or negative (excess of wrapped).
        return (underlyingBalance - wrappedBalanceAsUnderlying) / 2;
    }

    /**
     * @notice Returns the imbalance of a buffer in terms of the wrapped asset.
     * @dev The imbalance refers to the difference between the buffer's underlying asset balance and its wrapped asset
     * balance, both expressed in terms of the wrapped asset. A positive imbalance means the buffer holds more
     * wrapped assets than underlying assets, indicating that the excess wrapped should be unwrapped to restore
     * balance. Conversely, a negative imbalance means the buffer has more underlying assets than wrapped assets, so
     * during an unwrap operation, fewer wrapped tokens need to be unwrapped, and the surplus underlying tokens can be
     * returned to the caller.
     * For instance, consider the following scenario:
     * - buffer balances: 10 wrapped and 4 underlying
     * - wrapped rate: 2
     * - normalized buffer balances: 10 wrapped and 2 underlying as wrapped (2 underlying / rate)
     * - imbalance of wrapped = (10 - 2) / 2 = 4 wrapped
     * We need to unwrap 4 wrapped tokens to rebalance the buffer.
     * - 4 wrapped = 8 underlying
     * - final balances: 6 wrapped (10 existing - 4) and 12 underlying (4 existing + 8 new)
     * These balances are equal value, given the rate.
     */
    function getBufferWrappedImbalance(bytes32 bufferBalance, IERC4626 wrappedToken) internal view returns (int256) {
        int256 wrappedBalance = bufferBalance.getBalanceDerived().toInt256();

        int256 underlyingBalanceAsWrapped = 0;
        if (bufferBalance.getBalanceRaw() > 0) {
            // The buffer wrapped imbalance is used when unwrapping (it means, deposit wrapped and get underlying
            // tokens), so we use `previewWithdraw` to convert underlying balance to wrapped. The `withdraw` function
            // is used here, as it performs the inverse of a `redeem` operation.
            underlyingBalanceAsWrapped = wrappedToken.previewWithdraw(bufferBalance.getBalanceRaw()).toInt256();
        }

        // The return value may be positive (excess of wrapped) or negative (excess of underlying).
        return (wrappedBalance - underlyingBalanceAsWrapped) / 2;
    }
}
