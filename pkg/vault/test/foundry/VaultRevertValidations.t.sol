// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IProtocolFeeController } from "@balancer-labs/v3-interfaces/contracts/vault/IProtocolFeeController.sol";
import { VaultSwapParams, SwapKind } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IVaultExtension } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultExtension.sol";
import { IVaultErrors } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultErrors.sol";
import { IAuthorizer } from "@balancer-labs/v3-interfaces/contracts/vault/IAuthorizer.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";

import { BasicAuthorizerMock } from "../../contracts/test/BasicAuthorizerMock.sol";
import { BaseVaultTest } from "./utils/BaseVaultTest.sol";
import { Vault } from "../../contracts/Vault.sol";

/**
 * @notice A collection of "fail-fast" tests for revert conditions in the Vault.
 * @dev Grouped by concern into separate contracts to keep setup minimal and explicit.
 */

contract VaultSwapInputValidationTest is BaseVaultTest {
    function setUp() public virtual override {
        BaseVaultTest.setUp();
    }

    function _defaultSwapParams(
        SwapKind kind,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 amountGivenRaw
    ) internal view returns (VaultSwapParams memory) {
        return
            VaultSwapParams({
                kind: kind,
                pool: pool,
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                amountGivenRaw: amountGivenRaw,
                limitRaw: 0,
                userData: bytes("")
            });
    }

    function _expectVaultSwapRevert(VaultSwapParams memory params, bytes4 errorSelector) internal {
        vm.expectRevert(errorSelector);
        vault.unlock(abi.encodeCall(this.doVaultSwap, (params)));
    }

    /**
     * @dev Called by the Vault as part of `unlock`.
     * In this context, `msg.sender` is the Vault, so we call back into it to exercise `Vault.swap` validations.
     */
    function doVaultSwap(VaultSwapParams calldata params) external {
        IVault(msg.sender).swap(params);
    }

    function testSwapAmountGivenZeroRevertsExactIn() public {
        VaultSwapParams memory params = _defaultSwapParams(
            SwapKind.EXACT_IN,
            IERC20(address(usdc)),
            IERC20(address(dai)),
            0
        );
        _expectVaultSwapRevert(params, IVaultErrors.AmountGivenZero.selector);
    }

    function testSwapAmountGivenZeroRevertsExactOut() public {
        VaultSwapParams memory params = _defaultSwapParams(
            SwapKind.EXACT_OUT,
            IERC20(address(usdc)),
            IERC20(address(dai)),
            0
        );
        _expectVaultSwapRevert(params, IVaultErrors.AmountGivenZero.selector);
    }

    function testSwapAmountGivenZeroTakesPrecedenceOverSameToken() public {
        // `Vault.swap` checks `amountGivenRaw == 0` before checking `tokenIn == tokenOut`.
        VaultSwapParams memory params = _defaultSwapParams(
            SwapKind.EXACT_IN,
            IERC20(address(dai)),
            IERC20(address(dai)),
            0
        );
        _expectVaultSwapRevert(params, IVaultErrors.AmountGivenZero.selector);
    }

    function testSwapSameTokenRevertsExactIn() public {
        VaultSwapParams memory params = _defaultSwapParams(
            SwapKind.EXACT_IN,
            IERC20(address(dai)),
            IERC20(address(dai)),
            1
        );
        _expectVaultSwapRevert(params, IVaultErrors.CannotSwapSameToken.selector);
    }

    function testSwapSameTokenRevertsExactOut() public {
        VaultSwapParams memory params = _defaultSwapParams(
            SwapKind.EXACT_OUT,
            IERC20(address(dai)),
            IERC20(address(dai)),
            1
        );
        _expectVaultSwapRevert(params, IVaultErrors.CannotSwapSameToken.selector);
    }
}

/**
 * @dev Minimal vault extension that always returns the caller as the "vault".
 * When called from the Vault constructor, msg.sender is the Vault being deployed, so this satisfies
 * `vaultExtension.vault() == address(this)` without requiring precomputed addresses.
 */
contract GoodVaultExtension {
    function vault() external view returns (IVault) {
        return IVault(msg.sender);
    }

    // Minimal `IVaultAdmin` getters used by the `Vault` constructor.
    function getPauseWindowEndTime() external pure returns (uint32) {
        return 0;
    }

    function getBufferPeriodDuration() external pure returns (uint32) {
        return 0;
    }

    function getBufferPeriodEndTime() external pure returns (uint32) {
        return 0;
    }

    function getMinimumTradeAmount() external pure returns (uint256) {
        return 0;
    }

    function getMinimumWrapAmount() external pure returns (uint256) {
        return 0;
    }
}

/// @dev Minimal vault extension that returns a wrong vault address.
contract BadVaultExtension {
    IVault private immutable _vault;

    constructor(IVault wrongVault) {
        _vault = wrongVault;
    }

    function vault() external view returns (IVault) {
        return _vault;
    }
}

/// @dev Minimal protocol fee controller that returns a wrong vault address.
contract BadProtocolFeeController {
    IVault private immutable _vault;

    constructor(IVault wrongVault) {
        _vault = wrongVault;
    }

    function vault() external view returns (IVault) {
        return _vault;
    }
}

/// @dev Minimal protocol fee controller that always returns the caller as the "vault".
contract GoodProtocolFeeController {
    function vault() external view returns (IVault) {
        return IVault(msg.sender);
    }
}

contract VaultConstructorMisconfigurationTest is Test {
    function testVaultConstructorWrongVaultExtensionDeploymentReverts() public {
        BasicAuthorizerMock authorizer = new BasicAuthorizerMock();

        IVaultExtension badExtension = IVaultExtension(
            address(new BadVaultExtension(IVault(makeAddr("not-the-vault"))))
        );
        IProtocolFeeController goodFeeController = IProtocolFeeController(address(new GoodProtocolFeeController()));

        vm.expectRevert(IVaultErrors.WrongVaultExtensionDeployment.selector);
        new Vault(badExtension, IAuthorizer(address(authorizer)), goodFeeController);
    }

    function testVaultConstructorWrongProtocolFeeControllerDeploymentReverts() public {
        BasicAuthorizerMock authorizer = new BasicAuthorizerMock();
        IVaultExtension goodExtension = IVaultExtension(address(new GoodVaultExtension()));
        IProtocolFeeController badFeeController = IProtocolFeeController(
            address(new BadProtocolFeeController(IVault(makeAddr("not-the-vault"))))
        );

        vm.expectRevert(IVaultErrors.WrongProtocolFeeControllerDeployment.selector);
        new Vault(goodExtension, IAuthorizer(address(authorizer)), badFeeController);
    }
}

contract UnsettledDeltaCaller {
    function runSendToWithoutSettle(IVault vault, IERC20 token, address to, uint256 amount) external {
        // As msg.sender, we become the callback target for `Vault.unlock`.
        vault.unlock(abi.encodeCall(this._sendToWithoutSettle, (vault, token, to, amount)));
    }

    function _sendToWithoutSettle(IVault vault, IERC20 token, address to, uint256 amount) external {
        // Called by the Vault during unlock: msg.sender is the Vault (unlocked).
        // `sendTo` takes debt but we do not `settle`, so the Vault must revert at the end of the unlock.
        require(msg.sender == address(vault), "unexpected caller");
        vault.sendTo(token, to, amount);
    }

    function runSettleThenLeaveCreditUnsettled(IVault vault, IERC20 token, address to, uint256 settleAmount) external {
        // We fund this contract in the test so it can repay the Vault.
        // Then we settle and immediately consume almost all of the credit, leaving 1 wei credit behind.
        vault.unlock(abi.encodeCall(this._settleThenLeaveCreditUnsettled, (vault, token, to, settleAmount)));
    }

    function _settleThenLeaveCreditUnsettled(IVault vault, IERC20 token, address to, uint256 settleAmount) external {
        require(msg.sender == address(vault), "unexpected caller");
        require(settleAmount > 1, "settleAmount too small");

        // Transfer tokens in and settle to obtain credit.
        token.transfer(address(vault), settleAmount);
        vault.settle(token, settleAmount);

        // Consume all but 1 wei of the credit; leaving any non-zero delta must revert at end of unlock.
        vault.sendTo(token, to, settleAmount - 1);
    }
}

contract VaultUnsettledDeltasRevertTest is BaseVaultTest {
    function setUp() public virtual override {
        BaseVaultTest.setUp();
    }

    function testUnlockRevertsIfBalanceNotSettledAndRollsBack__Fuzz(uint256 rawAmount) public {
        UnsettledDeltaCaller caller = new UnsettledDeltaCaller();

        uint256 amount = bound(rawAmount, 1, poolInitAmount);
        uint256 bobDaiBefore = dai.balanceOf(bob);
        uint256 vaultDaiBefore = dai.balanceOf(address(vault));
        uint256 reservesBefore = vault.getReservesOf(dai);
        int256 deltaBefore = vault.getTokenDelta(dai);

        vm.expectRevert(IVaultErrors.BalanceNotSettled.selector);
        caller.runSendToWithoutSettle(IVault(address(vault)), dai, bob, amount);

        // Stronger than "expectRevert": ensure nothing leaked despite the attempted transfer.
        assertEq(dai.balanceOf(bob), bobDaiBefore, "bob DAI should rollback");
        assertEq(dai.balanceOf(address(vault)), vaultDaiBefore, "vault DAI should rollback");
        assertEq(vault.getReservesOf(dai), reservesBefore, "reserves should rollback");
        assertEq(vault.getTokenDelta(dai), deltaBefore, "delta should rollback");
    }

    function testUnlockRevertsIfCreditNotFullyConsumedAndRollsBack__Fuzz(uint256 rawSettleAmount) public {
        UnsettledDeltaCaller caller = new UnsettledDeltaCaller();

        uint256 settleAmount = bound(rawSettleAmount, 2, poolInitAmount);
        ERC20TestToken(address(dai)).mint(address(caller), settleAmount);

        uint256 bobDaiBefore = dai.balanceOf(bob);
        uint256 vaultDaiBefore = dai.balanceOf(address(vault));
        uint256 reservesBefore = vault.getReservesOf(dai);
        int256 deltaBefore = vault.getTokenDelta(dai);

        vm.expectRevert(IVaultErrors.BalanceNotSettled.selector);
        caller.runSettleThenLeaveCreditUnsettled(IVault(address(vault)), dai, bob, settleAmount);

        assertEq(dai.balanceOf(bob), bobDaiBefore, "bob DAI should rollback");
        assertEq(dai.balanceOf(address(vault)), vaultDaiBefore, "vault DAI should rollback");
        assertEq(vault.getReservesOf(dai), reservesBefore, "reserves should rollback");
        assertEq(vault.getTokenDelta(dai), deltaBefore, "delta should rollback");
    }
}
