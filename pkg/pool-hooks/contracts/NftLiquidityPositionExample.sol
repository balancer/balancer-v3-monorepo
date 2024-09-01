// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { IPermit2 } from "permit2/src/interfaces/IPermit2.sol";

import { TokenConfig } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/BasePoolTypes.sol";
import { IRouterCommon } from "@balancer-labs/v3-interfaces/contracts/vault/IRouterCommon.sol";
import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import {
    LiquidityManagement,
    HookFlags,
    AddLiquidityKind,
    RemoveLiquidityKind,
    AddLiquidityParams
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { BaseHooks } from "@balancer-labs/v3-vault/contracts/BaseHooks.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";

import { MinimalRouter } from "./MinimalRouter.sol";

/// @notice Mint an NFT to pool depositors, and charge a decaying exit fee upon withdrawal.
contract NftLiquidityPositionExample is MinimalRouter, ERC721, BaseHooks {
    using FixedPoint for uint256;

    // This contract uses timestamps to update its withdrawal fee over time.
    //solhint-disable not-rely-on-time

    // Initial fee of 10%.
    uint256 public constant INITIAL_FEE_PERCENTAGE = 10e16;
    uint256 public constant ONE_PERCENT = 1e16;
    // After this number of days the fee will be 0%.
    uint256 public constant DECAY_PERIOD_DAYS = 10;

    // `tokenId` uniquely identifies the NFT minted upon deposit.
    mapping(uint256 tokenId => uint256 bptAmount) public bptAmount;
    mapping(uint256 tokenId => uint256 timestamp) public startTime;
    mapping(uint256 tokenId => address pool) public nftPool;

    // NFT unique identifier.
    uint256 private _nextTokenId;

    /**
     * @notice A new `NftLiquidityPositionExample` contract has been registered successfully for a given pool.
     * @dev If the registration fails the call will revert, so there will be no event.
     * @param hooksContract This contract
     * @param pool The pool on which the hook was registered
     */
    event NftLiquidityPositionExampleRegistered(address indexed hooksContract, address indexed pool);

    /**
     * @notice A user has added liquidity to an associated pool, and received an NFT.
     * @param nftHolder The user who added liquidity to earn the NFT
     * @param pool The pool that received the liquidity
     * @param nftId The id of the newly minted NFT
     */
    event LiquidityPositionNftMinted(address indexed nftHolder, address indexed pool, uint256 nftId);

    /**
     * @notice A user has added liquidity to an associated pool, and received an NFT.
     * @param nftHolder The NFT holder who withdrew liquidity in exchange for the NFT
     * @param pool The pool from which the NFT holder withdrew liquidity
     * @param nftId The id of the NFT that was burned
     */
    event LiquidityPositionNftBurned(address indexed nftHolder, address indexed pool, uint256 nftId);

    /**
     * @notice An NFT holder withdrew liquidity during the decay period, incurring an exit fee.
     * @param nftHolder The NFT holder who withdrew liquidity in exchange for the NFT
     * @param pool The pool from which the NFT holder withdrew liquidity
     * @param feeToken The address of the token in which the fee was charged
     * @param feeAmount The amount of the fee, in native token decimals
     */
    event ExitFeeCharged(address indexed nftHolder, address indexed pool, IERC20 indexed feeToken, uint256 feeAmount);

    /**
     * @notice Hooks functions called from an external router.
     * @dev This contract inherits both `MinimalRouter` and `BaseHooks`, and functions as is its own router.
     * @param router The address of the router
     */
    error CannotUseExternalRouter(address router);

    /**
     * @notice The pool does not support adding liquidity through donation.
     * @dev There is an existing similar error (IVaultErrors.DoesNotSupportDonation), but hooks should not throw
     * "Vault" errors.
     */
    error PoolDoesNotSupportDonation();

    /**
     * @notice The pool supports adding unbalanced liquidity.
     * @dev There is an existing similar error (IVaultErrors.DoesNotSupportUnbalancedLiquidity), but hooks should not
     * throw "Vault" errors.
     */
    error PoolSupportsUnbalancedLiquidity();

    /**
     * @notice Attempted withdrawal of an NFT-associated position by an address that is not the owner.
     * @param withdrawer The address attempting to withdraw
     * @param owner The owner of the associated NFT
     * @param nftId The id of the NFT
     */
    error WithdrawalByNonOwner(address withdrawer, address owner, uint256 nftId);

    modifier onlySelfRouter(address router) {
        _ensureSelfRouter(router);
        _;
    }

    constructor(
        IVault vault,
        IWETH weth,
        IPermit2 permit2
    ) MinimalRouter(vault, weth, permit2) ERC721("BalancerLiquidityProvider", "BAL_LP") {
        // solhint-disable-previous-line no-empty-blocks
    }

    /***************************************************************************
                                  Router Functions
    ***************************************************************************/

    function addLiquidityProportional(
        address pool,
        uint256[] memory maxAmountsIn,
        uint256 exactBptAmountOut,
        bool wethIsEth,
        bytes memory userData
    ) external payable saveSender returns (uint256[] memory amountsIn) {
        // Do addLiquidity operation - BPT is minted to this contract.
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
        // Store the initial liquidity amount associated with the NFT.
        bptAmount[tokenId] = exactBptAmountOut;
        // Store the initial start time associated with the NFT.
        startTime[tokenId] = block.timestamp;
        // Store the pool/bpt address associated with the NFT.
        nftPool[tokenId] = pool;
        // Mint the associated NFT to sender.
        _safeMint(msg.sender, tokenId);

        emit LiquidityPositionNftMinted(msg.sender, pool, tokenId);
    }

    function removeLiquidityProportional(
        uint256 tokenId,
        uint256[] memory minAmountsOut,
        bool wethIsEth
    ) external payable saveSender returns (uint256[] memory amountsOut) {
        // Ensure the user owns the NFT.
        address nftOwner = ownerOf(tokenId);

        if (nftOwner != msg.sender) {
            revert WithdrawalByNonOwner(msg.sender, nftOwner, tokenId);
        }

        address pool = nftPool[tokenId];

        // Do removeLiquidity operation - tokens sent to msg.sender.
        amountsOut = _removeLiquidityProportional(
            pool,
            address(this),
            msg.sender,
            bptAmount[tokenId],
            minAmountsOut,
            wethIsEth,
            abi.encode(tokenId) // tokenId is passed to index fee data in hook
        );

        // Set all associated NFT data to 0.
        bptAmount[tokenId] = 0;
        startTime[tokenId] = 0;
        nftPool[tokenId] = address(0);
        // Burn the NFT
        _burn(tokenId);

        emit LiquidityPositionNftBurned(msg.sender, pool, tokenId);
    }

    /***************************************************************************
                                  Hook Functions
    ***************************************************************************/

    /// @inheritdoc BaseHooks
    function onRegister(
        address,
        address pool,
        TokenConfig[] memory,
        LiquidityManagement calldata liquidityManagement
    ) public override onlyVault returns (bool) {
        // This hook requires donation support to work (see above).
        if (liquidityManagement.enableDonation == false) {
            revert PoolDoesNotSupportDonation();
        }
        if (liquidityManagement.disableUnbalancedLiquidity == false) {
            revert PoolSupportsUnbalancedLiquidity();
        }

        emit NftLiquidityPositionExampleRegistered(address(this), pool);

        return true;
    }

    /// @inheritdoc BaseHooks
    function getHookFlags() public pure override returns (HookFlags memory) {
        HookFlags memory hookFlags;
        // `enableHookAdjustedAmounts` must be true for all contracts that modify the `amountCalculated`
        // in after hooks. Otherwise, the Vault will ignore any "hookAdjusted" amounts, and the transaction
        // might not settle. (It should be false if the after hooks do something else.)
        hookFlags.enableHookAdjustedAmounts = true;
        hookFlags.shouldCallBeforeAddLiquidity = true;
        hookFlags.shouldCallAfterRemoveLiquidity = true;
        return hookFlags;
    }

    /// @inheritdoc BaseHooks
    function onBeforeAddLiquidity(
        address router,
        address,
        AddLiquidityKind,
        uint256[] memory,
        uint256,
        uint256[] memory,
        bytes memory
    ) public view override onlySelfRouter(router) returns (bool) {
        // We only allow addLiquidity via the Router/Hook itself (as it must custody BPT).
        return true;
    }

    /// @inheritdoc BaseHooks
    function onAfterRemoveLiquidity(
        address router,
        address pool,
        RemoveLiquidityKind,
        uint256,
        uint256[] memory,
        uint256[] memory amountsOutRaw,
        uint256[] memory,
        bytes memory userData
    ) public override onlySelfRouter(router) returns (bool, uint256[] memory hookAdjustedAmountsOutRaw) {
        // We only allow removeLiquidity via the Router/Hook itself so that fee is applied correctly.
        uint256 tokenId = abi.decode(userData, (uint256));
        hookAdjustedAmountsOutRaw = amountsOutRaw;
        uint256 currentFee = getCurrentFeePercentage(tokenId);
        if (currentFee > 0) {
            hookAdjustedAmountsOutRaw = _takeFee(IRouterCommon(router).getSender(), pool, amountsOutRaw, currentFee);
        }
        return (true, hookAdjustedAmountsOutRaw);
    }

    /***************************************************************************
                                Off-chain Getters
    ***************************************************************************/

    /**
     * @notice Get the instantaneous value of the fee at the current block.
     * @param tokenId The fee token
     * @return feePercentage The current fee percentage
     */
    function getCurrentFeePercentage(uint256 tokenId) public view returns (uint256 feePercentage) {
        // Calculate the number of days that have passed since startTime
        uint256 daysPassed = (block.timestamp - startTime[tokenId]) / 1 days;
        if (daysPassed < DECAY_PERIOD_DAYS) {
            // decreasing fee by 1% per day
            feePercentage = INITIAL_FEE_PERCENTAGE - ONE_PERCENT * daysPassed;
        }
    }

    // Internal Functions

    function _takeFee(
        address nftHolder,
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

            emit ExitFeeCharged(nftHolder, pool, tokens[i], exitFee);
        }

        // Donates accrued fees back to LPs.
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

    function _ensureSelfRouter(address router) private view {
        if (router != address(this)) {
            revert CannotUseExternalRouter(router);
        }
    }
}
