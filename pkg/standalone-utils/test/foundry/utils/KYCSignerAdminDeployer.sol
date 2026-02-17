// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { KYCSignerAdmin } from "../../../contracts/KYCSignerAdmin.sol";

/**
 * @notice Deployer for `KYCSignerAdmin`.
 * @dev Can be inherited by any test base that needs the KYC signer singleton. Not reusing hardhat artifacts here, as
 * the KYCSignerAdmin is a very simple contract and this allows the tests to be more self-contained and not have to
 * deal with its use across multiple packages.
 */
contract KYCSignerAdminDeployer {
    function deployKYCSignerAdmin(address owner, address signer) internal returns (KYCSignerAdmin) {
        return new KYCSignerAdmin(owner, signer);
    }
}
