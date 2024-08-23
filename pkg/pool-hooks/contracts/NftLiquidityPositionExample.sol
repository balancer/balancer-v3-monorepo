// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IHooks } from "@balancer-labs/v3-interfaces/contracts/vault/IHooks.sol";
import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import {
    TokenConfig,
    LiquidityManagement,
    HookFlags,
    AddLiquidityKind,
    RemoveLiquidityKind,
    PoolSwapParams,
    AfterSwapParams,
    AddLiquidityParams
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { MinimalRouter } from "./MinimalRouter.sol";

contract NftRouter is MinimalRouter, ERC721, IHooks {
    using FixedPoint for uint256;
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
        bool wethIsEth
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
            abi.encode(tokenId) // tokenId is passed to index fee data in hook
        );

        // Set all associated NFT data to 0
        bptAmount[tokenId] = 0;
        startTime[tokenId] = 0;
        bpt[tokenId] = address(0);
        // Burn the NFT
        _burn(tokenId);
    }

    /***************************************************************************
                                 Hook Logic
    ***************************************************************************/

    /**
     * @dev The pool does not support adding liquidity through donation.
     * There is an existing similar error (IVaultErrors.DoesNotSupportDonation), but hooks should not throw
     * "Vault" errors.
     */
    error PoolDoesNotSupportDonation();

    function onRegister(
        address,
        address,
        TokenConfig[] memory,
        LiquidityManagement calldata liquidityManagement
    ) public virtual returns (bool) {
        // This hook requires donation support to work (see above).
        if (liquidityManagement.enableDonation == false) {
            revert PoolDoesNotSupportDonation();
        }

        return true;
    }

    function getHookFlags() public view virtual returns (HookFlags memory) {
        HookFlags memory hookFlags;
        // `enableHookAdjustedAmounts` must be true for all contracts that modify the `amountCalculated`
        // in after hooks. Otherwise, the Vault will ignore any "hookAdjusted" amounts, and the transaction
        // might not settle. (It should be false if the after hooks do something else.)
        hookFlags.enableHookAdjustedAmounts = true;
        hookFlags.shouldCallAfterRemoveLiquidity = true;
        hookFlags.shouldCallBeforeAddLiquidity = true;
        return hookFlags;
    }

    function onBeforeAddLiquidity(
        address router,
        address,
        AddLiquidityKind,
        uint256[] memory,
        uint256,
        uint256[] memory,
        bytes memory
    ) public virtual returns (bool) {
        // We only allow addLiquidity via the Router/Hook itself (as it must custody BPT)
        require(router == address(this), "Can't use external router");
        return true;
    }

    function onAfterRemoveLiquidity(
        address router,
        address pool,
        RemoveLiquidityKind,
        uint256,
        uint256[] memory,
        uint256[] memory amountsOutRaw,
        uint256[] memory,
        bytes memory userData
    ) public virtual returns (bool, uint256[] memory hookAdjustedAmountsOutRaw) {
        // We only allow removeLiquidity via the Router/Hook itself so that fee is applied correctly
        require(router == address(this), "Can't use external router");

        uint256 tokenId = abi.decode(userData, (uint256));
        hookAdjustedAmountsOutRaw = amountsOutRaw;
        // Calculate the number of days that have passed since startTime
        uint256 daysPassed = (block.timestamp - startTime[tokenId]) / 1 days;
        // Initial fee of 10%
        uint256 initialFee = 10e16;
        if (daysPassed < 10) {
            // decreasing fee by 1% per day
            uint256 currentFee = initialFee - 1e16 * daysPassed;
            hookAdjustedAmountsOutRaw = takeFee(pool, amountsOutRaw, currentFee);
        }
        return (true, hookAdjustedAmountsOutRaw);
    }

    function takeFee(
        address pool,
        uint256[] memory amountsOutRaw,
        uint256 currentFee
    ) private returns (uint256[] memory hookAdjustedAmountsOutRaw) {
        hookAdjustedAmountsOutRaw = amountsOutRaw;
        IERC20[] memory tokens = _vault.getPoolTokens(pool);
        uint256[] memory accruedFees = new uint256[](tokens.length);
        // Charge fees proportional to the `amountOut` of each token.
        for (uint256 i = 0; i < amountsOutRaw.length; i++) {
            uint256 exitFee = amountsOutRaw[i].mulDown(currentFee);
            accruedFees[i] = exitFee;
            hookAdjustedAmountsOutRaw[i] -= exitFee;
            // Fees don't need to be transferred to the hook, because donation will redeposit them in the vault.
            // In effect, we will transfer a reduced amount of tokensOut to the caller, and leave the remainder
            // in the pool balance.
        }

        // Donates accrued fees back to LPs
        _vault.addLiquidity(
            AddLiquidityParams({
                pool: pool,
                to: msg.sender, // It would mint BPTs to router, but it's a donation so no BPT is minted
                maxAmountsIn: accruedFees, // Donate all accrued fees back to the pool (i.e. to the LPs)
                minBptAmountOut: 0, // Donation does not return BPTs, any number above 0 will revert
                kind: AddLiquidityKind.DONATION,
                userData: bytes("") // User data is not used by donation, so we can set it to an empty string
            })
        );
    }

    function onBeforeInitialize(uint256[] memory, bytes memory) public virtual returns (bool) {
        return false;
    }

    function onAfterInitialize(uint256[] memory, uint256, bytes memory) public virtual returns (bool) {
        return false;
    }

    function onAfterAddLiquidity(
        address,
        address,
        AddLiquidityKind,
        uint256[] memory,
        uint256[] memory amountsInRaw,
        uint256,
        uint256[] memory,
        bytes memory
    ) public virtual returns (bool, uint256[] memory) {
        return (false, amountsInRaw);
    }

    function onBeforeRemoveLiquidity(
        address,
        address,
        RemoveLiquidityKind,
        uint256,
        uint256[] memory,
        uint256[] memory,
        bytes memory
    ) public virtual returns (bool) {
        return false;
    }

    function onBeforeSwap(PoolSwapParams calldata, address) public virtual returns (bool) {
        // return false to trigger an error if shouldCallBeforeSwap is true but this function is not overridden.
        return false;
    }

    function onAfterSwap(AfterSwapParams calldata) public virtual returns (bool, uint256) {
        // return false to trigger an error if shouldCallAfterSwap is true but this function is not overridden.
        // The second argument is not used.
        return (false, 0);
    }

    function onComputeDynamicSwapFeePercentage(
        PoolSwapParams calldata,
        address,
        uint256
    ) public view virtual returns (bool, uint256) {
        return (false, 0);
    }
}
