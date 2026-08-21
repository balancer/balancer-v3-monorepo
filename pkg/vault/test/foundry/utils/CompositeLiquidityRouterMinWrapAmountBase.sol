// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";

import { ERC4626TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC4626TestToken.sol";
import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/test/ArrayHelpers.sol";

import { BalancerPoolToken } from "../../../contracts/BalancerPoolToken.sol";
import { BaseVaultTest } from "./BaseVaultTest.sol";

/**
 * @notice Shared fixture for the composite router suites that run at the production Vault minimums.
 * @dev `BaseVaultTest` defaults to a minimum wrap amount of 1 and no minimum trade amount, so no other composite
 * router suite can reach the band in which the buffer refuses a non-zero amount. Suites extending this one raise
 * both to the production values and share one pool: a 6-decimal wrapper, whose raw proportional share can round to
 * zero or into the refused band at burns that still pay the 18-decimal token in full, paired with an 18-decimal one.
 */
abstract contract CompositeLiquidityRouterMinWrapAmountBase is BaseVaultTest {
    using ArrayHelpers for *;

    // Smallest raw wrapped amount the buffer accepts, at a redeem rate of exactly one.
    uint256 internal constant _FIRST_ACCEPTED_RAW = PRODUCTION_MIN_WRAP_AMOUNT + 2;

    uint256 internal constant _WA6_POOL_BALANCE = 1e6; // 1.0 unit of a 6-decimal wrapper
    uint256 internal constant _WADAI_POOL_BALANCE = 1e6 * 1e18;
    uint256 internal constant _WA6_BUFFER_UNDERLYING = 1e5 * 1e6;

    ERC4626TestToken internal _wa6;

    uint256 internal _wa6Idx;
    uint256 internal _waDaiIdx;

    function setUp() public virtual override {
        vaultMockMinTradeAmount = PRODUCTION_MIN_TRADE_AMOUNT;
        vaultMockMinWrapAmount = PRODUCTION_MIN_WRAP_AMOUNT;

        BaseVaultTest.setUp();

        authorizer.grantRole(vault.getActionId(IVaultAdmin.pauseVaultBuffers.selector), admin);
    }

    function createPool() internal override returns (address newPool, bytes memory poolArgs) {
        _wa6 = createERC4626("Wrapped USDC-6", "wa6", 6, usdc6Decimals);

        (_wa6Idx, _waDaiIdx) = getSortedIndexes(address(_wa6), address(waDAI));

        return _createPool([address(_wa6), address(waDAI)].toMemoryArray(), "minWrapPool");
    }

    function initPool() internal override {
        // The wrapper is created inside `createPool`, after the base approvals ran, so it needs its own.
        approveForWrapper(_wa6, usdc6Decimals);

        vm.startPrank(lp);
        _wa6.deposit(_WA6_BUFFER_UNDERLYING + _WA6_POOL_BALANCE, lp);
        bufferRouter.initializeBuffer(_wa6, _WA6_BUFFER_UNDERLYING, _wa6.previewDeposit(_WA6_BUFFER_UNDERLYING), 0);
        bufferRouter.initializeBuffer(waDAI, _WA6_BUFFER_UNDERLYING * 1e12, waDAI.previewDeposit(1e5 * 1e18), 0);

        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[_wa6Idx] = _WA6_POOL_BALANCE;
        amountsIn[_waDaiIdx] = _WADAI_POOL_BALANCE;

        _initPool(pool, amountsIn, 0);
        vm.stopPrank();
    }

    /// @dev A flag array covering every pool token, as the wrap/unwrap arguments expect.
    function _setupTrueBoolArray(uint256 length) internal pure returns (bool[] memory) {
        bool[] memory boolArray = new bool[](length);
        for (uint256 i = 0; i < boolArray.length; i++) {
            boolArray[i] = true;
        }
        return boolArray;
    }

    /// @dev The nested entry point's output declaration for the shared pool: both underlyings, both unwrapped.
    function _tokenLists() internal view returns (address[] memory tokensOut, address[] memory tokensToUnwrap) {
        (uint256 usdc6Idx, uint256 daiIdx) = getSortedIndexes(address(usdc6Decimals), address(dai));

        tokensOut = new address[](2);
        tokensOut[usdc6Idx] = address(usdc6Decimals);
        tokensOut[daiIdx] = address(dai);

        tokensToUnwrap = new address[](2);
        tokensToUnwrap[0] = address(_wa6);
        tokensToUnwrap[1] = address(waDAI);
    }

    /// @dev Raw pool-token amounts a proportional burn of `bptIn` would return, from the plain Router's query.
    function _rawAmountsOut(uint256 bptIn) internal returns (uint256[] memory amountsOut) {
        uint256 snapshotId = vm.snapshotState();
        _prankStaticCall();
        amountsOut = router.queryRemoveLiquidityProportional(pool, bptIn, address(this), bytes(""));
        vm.revertToState(snapshotId);
    }

    /// @dev Largest `bptIn` whose raw wa6 output is at most `targetRaw`.
    function _burnForRawWa6(uint256 targetRaw) internal returns (uint256) {
        uint256 low = PRODUCTION_MIN_TRADE_AMOUNT;
        uint256 high = BalancerPoolToken(pool).balanceOf(lp);

        while (low < high) {
            uint256 mid = (low + high + 1) / 2;
            if (_rawAmountsOut(mid)[_wa6Idx] <= targetRaw) {
                low = mid;
            } else {
                high = mid - 1;
            }
        }

        return low;
    }
}
