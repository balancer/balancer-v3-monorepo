// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { MinimalRouter } from "./MinimalRouter.sol";

contract NftRouter is MinimalRouter, ERC721 {
    uint256 private _nextTokenId;
    mapping(uint256 => uint256) public bptAmount;
    mapping(uint256 => uint256) public startTime;
    mapping(uint256 => address) public bpt;

    constructor(
        IVault vault,
        IWETH weth,
        IPermit2 permit2
    ) MinimalRouter(vault, weth, permit2) ERC721("BalancerLiquidityProvider", "BAL_LP") {
        // solhint-disable-previous-line no-empty-blocks
    }

    function addLiquidityProportional(
        address pool,
        uint256[] memory maxAmountsIn,
        uint256 exactBptAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable saveSender returns (uint256[] memory amountsIn) {
        // Do addLiquidity operation - BPT is minted to this contract
        amountsIn = _addLiquidityProportional(
            pool,
            msg.sender,
            address(this),
            maxAmountsIn,
            exactBptAmountOut,
            wethIsEth,
            userData
        );

        uint256 tokenId = _nextTokenId++;
        // Store the initial liquidity amount associated with the NFT
        bptAmount[tokenId] = exactBptAmountOut;
        // Store the initial start time associated with the NFT
        startTime[tokenId] = block.timestamp;
        // Store the pool/bpt address associated with the NFT
        bpt[tokenId] = pool;
        // Mint the associated NFT to sender
        _safeMint(msg.sender, tokenId);
    }

    function removeLiquidityProportional(
        uint256 tokenId,
        uint256[] memory minAmountsOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable saveSender returns (uint256[] memory amountsOut) {
        // Ensure the user owns the NFT
        require(ownerOf(tokenId) == msg.sender, "You don't own this NFT");

        // Do removeLiquidity operation - tokens sent to msg.sender
        amountsOut = _removeLiquidityProportional(
            bpt[tokenId],
            address(this),
            msg.sender,
            bptAmount[tokenId],
            minAmountsOut,
            wethIsEth,
            userData
        );

        // Set all associated NFT data to 0
        bptAmount[tokenId] = 0;
        startTime[tokenId] = 0;
        bpt[tokenId] = address(0);
        // Burn the NFT
        _burn(tokenId);
    }
}
