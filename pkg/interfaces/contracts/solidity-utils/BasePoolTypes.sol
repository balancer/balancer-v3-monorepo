// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./helpers/IRateProvider.sol";

enum Rounding {
    ROUND_UP,
    ROUND_DOWN
}

/**
 * @notice Token types supported by the Vault.
 * @dev In general, pools may contain any combination of these tokens.
 *
 * STANDARD tokens (e.g., BAL, WETH) have no rate provider.
 * WITH_RATE tokens (e.g., wstETH) require a rate provider. These may be tokens like wstETH, which need to be wrapped
 * because the underlying stETH token is rebasing, and such tokens are unsupported by the Vault. They may also be
 * tokens like sEUR, which track an underlying asset, but are not yield-bearing. Finally, this encompasses
 * yield-bearing ERC4626 tokens, which can be used to facilitate swaps without requiring wrapping or unwrapping
 * in most cases. The `paysYieldFees` flag can be used to indicate whether a token is yield-bearing (e.g., waDAI),
 * not yield-bearing (e.g., sEUR), or yield-bearing but exempt from fees (e.g., in certain nested pools, where
 * yield fees are charged elsewhere).
 *
 * NB: STANDARD must always be the first enum element, so that newly initialized data structures default to Standard.
 */
enum TokenType {
    STANDARD,
    WITH_RATE
}

/**
 * @notice Encapsulate the data required for the Vault to support a token of the given type.
 * @dev For STANDARD tokens, the rate provider address must be 0, and paysYieldFees must be false. All WITH_RATE tokens
 * need a rate provider, and may or may not be yield-bearing.
 *
 * At registration time, it is useful to include the token address along with the token parameters in the structure
 * passed to `registerPool`, as the alternative would be parallel arrays, which would be error prone and require
 * validation checks. `TokenConfig` is only used for registration, and is never put into storage (see `TokenInfo`).
 *
 * @param token The token address
 * @param tokenType The token type (see the enum for supported types)
 * @param rateProvider The rate provider for a token (see further documentation above)
 * @param paysYieldFees Flag indicating whether yield fees should be charged on this token
 */
struct TokenConfig {
    IERC20 token;
    TokenType tokenType;
    IRateProvider rateProvider;
    bool paysYieldFees;
}
