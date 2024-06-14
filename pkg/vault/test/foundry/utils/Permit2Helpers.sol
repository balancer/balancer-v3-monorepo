// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { Script } from "forge-std/Script.sol";

import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";
import { IAllowanceTransfer } from "permit2/src/interfaces/IAllowanceTransfer.sol";
import { DeployPermit2 } from "permit2/test/utils/DeployPermit2.sol";

import { IEIP712 } from "permit2/src/interfaces/IEIP712.sol";

contract Permit2Helpers is Script {
    IPermit2 internal permit2;

    constructor() {
        DeployPermit2 _deployPermit2 = new DeployPermit2();
        permit2 = IPermit2(_deployPermit2.deployPermit2());
        vm.label(address(permit2), "permit2");
    }

    bytes32 private constant _PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    bytes32 internal constant _PERMIT_DETAILS_TYPEHASH =
        keccak256("PermitDetails(address token,uint160 amount,uint48 expiration,uint48 nonce)");

    bytes32 internal constant _PERMIT_BATCH_TYPEHASH =
        keccak256(
            "PermitBatch(PermitDetails[] details,address spender,uint256 sigDeadline)PermitDetails(address token,uint160 amount,uint48 expiration,uint48 nonce)"
        );

    bytes32 internal constant _PERMIT_SINGLE_TYPEHASH =
        keccak256(
            "PermitSingle(PermitDetails details,address spender,uint256 sigDeadline)PermitDetails(address token,uint160 amount,uint48 expiration,uint48 nonce)"
        );

    function getPermitSignature(
        IEIP712 token,
        address owner,
        address spender,
        uint256 amount,
        uint256 nonce,
        uint256 deadline,
        uint256 key
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        (v, r, s) = vm.sign(
            key,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    token.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(_PERMIT_TYPEHASH, owner, spender, amount, nonce, deadline))
                )
            )
        );
    }

    function getPermit2Batch(
        address spender,
        address[] memory tokens,
        uint160 amount,
        uint48 expiration,
        uint48 nonce
    ) internal view returns (IAllowanceTransfer.PermitBatch memory) {
        IAllowanceTransfer.PermitDetails[] memory details = new IAllowanceTransfer.PermitDetails[](tokens.length);

        for (uint256 i = 0; i < tokens.length; ++i) {
            details[i] = IAllowanceTransfer.PermitDetails({
                token: tokens[i],
                amount: amount,
                expiration: expiration,
                nonce: nonce
            });
        }

        return
            IAllowanceTransfer.PermitBatch({ details: details, spender: spender, sigDeadline: block.timestamp + 100 });
    }

    function getPermit2BatchSignature(
        address spender,
        address[] memory tokens,
        uint160 amount,
        uint48 expiration,
        uint48 nonce,
        uint256 key
    ) internal view returns (bytes memory sig) {
        IAllowanceTransfer.PermitBatch memory permit = getPermit2Batch(spender, tokens, amount, expiration, nonce);
        bytes32[] memory permitHashes = new bytes32[](permit.details.length);
        for (uint256 i = 0; i < permit.details.length; ++i) {
            permitHashes[i] = keccak256(abi.encode(_PERMIT_DETAILS_TYPEHASH, permit.details[i]));
        }
        bytes32 msgHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                IEIP712(address(permit2)).DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        _PERMIT_BATCH_TYPEHASH,
                        keccak256(abi.encodePacked(permitHashes)),
                        permit.spender,
                        permit.sigDeadline
                    )
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, msgHash);
        return bytes.concat(r, s, bytes1(v));
    }
}
