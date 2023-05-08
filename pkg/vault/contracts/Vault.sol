// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/IAuthorizer.sol";

import "./VaultAuthorization.sol";
import "./FlashLoans.sol";
import "./Swaps.sol";

/**
 * @dev The `Vault` is Balancer V2's core contract. A single instance of it exists for the entire network, and it is the
 * entity used to interact with Pools by Liquidity Providers who join and exit them, Traders who swap, and Asset
 * Managers who withdraw and deposit tokens.
 *
 * The `Vault`'s source code is split among a number of sub-contracts, with the goal of improving readability and making
 * understanding the system easier. Most sub-contracts have been marked as `abstract` to explicitly indicate that only
 * the full `Vault` is meant to be deployed.
 *
 * Roughly speaking, these are the contents of each sub-contract:
 *
 *  - `AssetManagers`: Pool token Asset Manager registry, and Asset Manager interactions.
 *  - `Fees`: set and compute protocol fees.
 *  - `FlashLoans`: flash loan transfers and fees.
 *  - `PoolBalances`: Pool joins and exits.
 *  - `PoolRegistry`: Pool registration, ID management, and basic queries.
 *  - `PoolTokens`: Pool token registration and registration, and balance queries.
 *  - `Swaps`: Pool swaps.
 *  - `UserBalance`: manage user balances (Internal Balance operations and external balance transfers)
 *  - `VaultAuthorization`: access control, relayers and signature validation.
 *
 * Additionally, the different Pool specializations are handled by the `GeneralPoolsBalance`,
 * `MinimalSwapInfoPoolsBalance` and `TwoTokenPoolsBalance` sub-contracts, which in turn make use of the
 * `BalanceAllocation` library.
 *
 * The most important goal of the `Vault` is to make token swaps use as little gas as possible. This is reflected in a
 * multitude of design decisions, from minor things like the format used to store Pool IDs, to major features such as
 * the different Pool specialization settings.
 *
 * Finally, the large number of tasks carried out by the Vault means its bytecode is very large, close to exceeding
 * the contract size limit imposed by EIP 170 (https://eips.ethereum.org/EIPS/eip-170). Manual tuning of the source code
 * was required to improve code generation and bring the bytecode size below this limit. This includes extensive
 * utilization of `internal` functions (particularly inside modifiers), usage of named return arguments, dedicated
 * storage access methods, dynamic revert reason generation, and usage of inline assembly, to name a few.
 */
contract Vault is VaultAuthorization, FlashLoans, Swaps {
    constructor(
        IAuthorizer authorizer,
        IWETH weth,
        uint256 pauseWindowDuration,
        uint256 bufferPeriodDuration
    ) VaultAuthorization(authorizer) AssetHelpers(weth) TemporarilyPausable(pauseWindowDuration, bufferPeriodDuration) {
        // solhint-disable-previous-line no-empty-blocks
    }

    function setPaused(bool paused) external override nonReentrant authenticate {
        _setPaused(paused);
    }

    // solhint-disable-next-line func-name-mixedcase
    function WETH() external view override returns (IWETH) {
        return _WETH();
    }
}
