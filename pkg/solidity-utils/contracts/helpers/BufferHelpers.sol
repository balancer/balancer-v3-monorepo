// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { PackedTokenBalance } from "./PackedTokenBalance.sol";

library BufferHelpers {
    using PackedTokenBalance for bytes32;

    /**
     * @dev Underlying surplus is the amount of underlying that need to be wrapped for the buffer to be rebalanced.
     * For instance, consider the following scenario:
     * - buffer balances: 2 wrapped and 10 underlying
     * - wrapped rate: 2
     * - normalized buffer balances: 4 wrapped as underlying (2 wrapped * rate) and 10 underlying
     * - surplus of underlying = (10 - 4) / 2 = 3 underlying
     * We need to wrap 3 underlying tokens to consider the buffer rebalanced.
     * - 3 underlying = 1.5 wrapped
     * - final balances: 3.5 wrapped (2 existing + 1.5 new) and 7 underlying (10 existing - 3)
     */
    function getBufferUnderlyingSurplus(bytes32 bufferBalance, IERC4626 wrappedToken) internal view returns (uint256) {
        uint256 underlyingBalance = bufferBalance.getBalanceRaw();

        uint256 wrappedBalanceAsUnderlying = 0;
        if (bufferBalance.getBalanceDerived() > 0) {
            wrappedBalanceAsUnderlying = wrappedToken.convertToAssets(bufferBalance.getBalanceDerived());
        }

        uint256 surplus = 0;
        if (underlyingBalance > wrappedBalanceAsUnderlying) {
            unchecked {
                surplus = (underlyingBalance - wrappedBalanceAsUnderlying) / 2;
            }
        }
        return surplus;
    }

    /**
     * @dev Wrapped surplus is the amount of wrapped tokens that need to be unwrapped for the buffer to be rebalanced.
     * For instance, consider the following scenario:
     * - buffer balances: 10 wrapped and 4 underlying
     * - wrapped rate: 2
     * - normalized buffer balances: 10 wrapped and 2 underlying as wrapped (2 underlying / rate)
     * - surplus of wrapped = (10 - 2) / 2 = 4 wrapped
     * We need to unwrap 4 wrapped tokens to consider the buffer rebalanced.
     * - 4 wrapped = 8 underlying
     * - final balances: 6 wrapped (10 existing - 4) and 12 underlying (4 existing + 8 new)
     */
    function getBufferWrappedSurplus(bytes32 bufferBalance, IERC4626 wrappedToken) internal view returns (uint256) {
        uint256 wrappedBalance = bufferBalance.getBalanceDerived();

        uint256 underlyingBalanceAsWrapped = 0;
        if (bufferBalance.getBalanceRaw() > 0) {
            underlyingBalanceAsWrapped = wrappedToken.convertToShares(bufferBalance.getBalanceRaw());
        }

        uint256 surplus = 0;
        if (wrappedBalance > underlyingBalanceAsWrapped) {
            unchecked {
                surplus = (wrappedBalance - underlyingBalanceAsWrapped) / 2;
            }
        }
        return surplus;
    }
}
