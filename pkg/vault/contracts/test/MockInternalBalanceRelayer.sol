// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import "@balancer-labs/v3-interfaces/contracts/solidity-utils/openzeppelin/IERC20.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";

import "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";

contract MockInternalBalanceRelayer {
    IVault public vault;

    constructor(IVault _vault) {
        vault = _vault;
    }

    function depositAndWithdraw(
        address payable sender,
        IAsset asset,
        uint256[] memory depositAmounts,
        uint256[] memory withdrawAmounts
    ) public {
        InputHelpers.ensureInputLengthMatch(depositAmounts.length, withdrawAmounts.length);
        for (uint256 i = 0; i < depositAmounts.length; i++) {
            IVault.UserBalanceOp[] memory deposit = _buildUserBalanceOp(
                IVault.UserBalanceOpKind.DEPOSIT_INTERNAL,
                sender,
                asset,
                depositAmounts[i]
            );
            vault.manageUserBalance(deposit);

            IVault.UserBalanceOp[] memory withdraw = _buildUserBalanceOp(
                IVault.UserBalanceOpKind.WITHDRAW_INTERNAL,
                sender,
                asset,
                withdrawAmounts[i]
            );
            vault.manageUserBalance(withdraw);
        }
    }

    function _buildUserBalanceOp(
        IVault.UserBalanceOpKind kind,
        address payable sender,
        IAsset asset,
        uint256 amount
    ) internal pure returns (IVault.UserBalanceOp[] memory ops) {
        ops = new IVault.UserBalanceOp[](1);
        ops[0] = IVault.UserBalanceOp({ asset: asset, amount: amount, sender: sender, recipient: sender, kind: kind });
    }
}
