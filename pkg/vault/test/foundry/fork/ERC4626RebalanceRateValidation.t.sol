// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.4;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import { IRateProvider } from "@balancer-labs/v3-interfaces/contracts/vault/IRateProvider.sol";
import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IVaultAdmin } from "@balancer-labs/v3-interfaces/contracts/vault/IVaultAdmin.sol";
import { IBufferPool } from "@balancer-labs/v3-interfaces/contracts/vault/IBufferPool.sol";
import {
    TokenConfig,
    PoolConfig,
    SwapKind,
    TokenType
} from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IBasePool } from "@balancer-labs/v3-interfaces/contracts/vault/IBasePool.sol";
import { IWETH } from "@balancer-labs/v3-interfaces/contracts/solidity-utils/misc/IWETH.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { BasicAuthorizerMock } from "@balancer-labs/v3-solidity-utils/contracts/test/BasicAuthorizerMock.sol";
import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";
import { WETHTestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/WETHTestToken.sol";

import { Vault } from "@balancer-labs/v3-vault/contracts/Vault.sol";
import { Router } from "@balancer-labs/v3-vault/contracts/Router.sol";
import { VaultMock } from "@balancer-labs/v3-vault/contracts/test/VaultMock.sol";
import { PoolConfigBits, PoolConfigLib } from "@balancer-labs/v3-vault/contracts/lib/PoolConfigLib.sol";
import { BaseVaultTest } from "@balancer-labs/v3-vault/test/foundry/utils/BaseVaultTest.sol";

import { ERC4626BufferPoolFactoryMock } from "../utils/ERC4626BufferPoolFactoryMock.sol";
import { ERC4626BufferPoolMock } from "../utils/ERC4626BufferPoolMock.sol";
import "../utils/ERC4626TokenMock.sol";

contract ERC4626RebalanceRateValidation is BaseVaultTest {
    using ArrayHelpers for *;
    using FixedPoint for uint256;

    uint8 immutable WRAPPED_TOKEN_INDEX = 0;
    uint8 immutable BASE_TOKEN_INDEX = 1;

    ERC4626BufferPoolFactoryMock factory;
    ERC4626BufferPoolMock internal bufferPoolDai;
    ERC4626BufferPoolMock internal bufferPoolSand;

    IERC20 daiMainnet;
    IERC4626 wDAI;

    IERC20 sandMainnet;
    IERC4626 wSAND;

    uint256 constant BLOCK_NUMBER = 19314200;

    address constant DAI_ADDRESS = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address wDAI_ADDRESS;
    address constant SAND_ADDRESS = 0x3845badAde8e6dFF049820680d1F14bD3903a5d0;
    address wSAND_ADDRESS;

    // Owner of DAI and SAND in Mainnet
    address constant DONOR_WALLET_ADDRESS = 0x47ac0Fb4F2D84898e4D9E7b4DaB3C24507a6D503;

    address payable donor;

    uint256 constant BUFFER_BASE_TOKENS = 1e6 * 1e18;
    uint256 bufferDaiWrapped;
    uint256 bufferSandWrapped;

    uint256 constant DELTA = 1e12;

    uint256 internal bptAmountOutDai;
    uint256 internal bptAmountOutSand;

    uint256 constant SMALL_AMOUNT = 3e6;
    uint256 constant BIG_AMOUNT = 1e12;

    function setUp() public virtual override {
        vm.createSelectFork({ blockNumber: BLOCK_NUMBER, urlOrAlias: "mainnet" });

        donor = payable(DONOR_WALLET_ADDRESS);
        vm.label(donor, "TokenDonor");
        vm.label(DAI_ADDRESS, "DAI");
        vm.label(SAND_ADDRESS, "SAND");

        daiMainnet = IERC20(DAI_ADDRESS);
        sandMainnet = IERC20(SAND_ADDRESS);

        _createTokens();

        BaseVaultTest.setUp();
    }

    function createPool() internal override returns (address) {
        factory = new ERC4626BufferPoolFactoryMock(IVault(address(vault)), 365 days);
        authorizer.grantRole(vault.getActionId(IVaultAdmin.registerBufferPoolFactory.selector), alice);
        vm.prank(alice);
        vault.registerBufferPoolFactory(address(factory));

        bufferPoolDai = ERC4626BufferPoolMock(_createBuffer(wDAI));
        bufferPoolSand = ERC4626BufferPoolMock(_createBuffer(wSAND));

        return address(bufferPoolDai);
    }

    function initPool() internal override {
        _transferTokensFromDonorToUsers();
        // The swap calculation of the buffer is a bit imprecise to save gas,
        // so it needs to have some ERC20 to rebalance
        _transferTokensFromDonorToBuffers();
        _setPermissions();

        vm.startPrank(lp);

        // Creating DAI Buffer
        bufferDaiWrapped = wDAI.convertToShares(BUFFER_BASE_TOKENS);
        wDAI.deposit(BUFFER_BASE_TOKENS, address(lp));
        uint256[] memory amountsInDai = [uint256(bufferDaiWrapped), uint256(BUFFER_BASE_TOKENS)].toMemoryArray();
        bptAmountOutDai = router.initialize(
            address(bufferPoolDai),
            [wDAI_ADDRESS, DAI_ADDRESS].toMemoryArray().asIERC20(),
            amountsInDai,
            // Account for the precision loss
            BUFFER_BASE_TOKENS - DELTA - 1e6,
            false,
            bytes("")
        );

        // Creating SAND Buffer
        bufferSandWrapped = wSAND.convertToShares(BUFFER_BASE_TOKENS);
        wSAND.deposit(BUFFER_BASE_TOKENS, address(lp));
        uint256[] memory amountsInSand = [uint256(bufferSandWrapped), uint256(BUFFER_BASE_TOKENS)].toMemoryArray();
        bptAmountOutSand = router.initialize(
            address(bufferPoolSand),
            [wSAND_ADDRESS, SAND_ADDRESS].toMemoryArray().asIERC20(),
            amountsInSand,
            // Account for the precision loss
            BUFFER_BASE_TOKENS - DELTA - 1e6,
            false,
            bytes("")
        );
        vm.stopPrank();
    }

    function testInitializeDai__Fork() public {
        // Tokens are stored in the Vault
        assertEq(
            wDAI.balanceOf(address(vault)),
            bufferDaiWrapped,
            "Vault should have the deposited amount of wDai"
        );
        assertEq(
            daiMainnet.balanceOf(address(vault)),
            BUFFER_BASE_TOKENS,
            "Vault should have the deposited amount of DAI"
        );

        // Check if tokens are deposited in the pool
        (, , uint256[] memory balancesRaw, , ) = vault.getPoolTokenInfo(address(bufferPoolDai));
        assertEq(balancesRaw[0], bufferDaiWrapped, "wDai BufferPool balance should have the deposited amount of wDai");
        assertEq(balancesRaw[1], BUFFER_BASE_TOKENS, "wDai BufferPool balance should have the deposited amount of DAI");

        // should mint correct amount of BPT tokens for buffer
        // Account for the precision loss
        assertApproxEqAbs(
            bufferPoolDai.balanceOf(lp),
            bptAmountOutDai,
            DELTA,
            "lp should have the BPT issued by the wDai BufferPool"
        );
        assertApproxEqAbs(
            bptAmountOutDai,
            2 * BUFFER_BASE_TOKENS,
            DELTA,
            string.concat(
                "The amount of BPT issued by the wDai BufferPool should be very ",
                "close to the sum of DAI+wDAI (or 2 * DAI, as the buffer is balanced)"
            )
        );
    }

    function testInitializeSand__Fork() public {
        // Tokens are stored in the Vault
        assertEq(
            wSAND.balanceOf(address(vault)),
            bufferSandWrapped,
            "Vault should have the deposited amount of wSand"
        );
        assertEq(
            sandMainnet.balanceOf(address(vault)),
            BUFFER_BASE_TOKENS,
            "Vault should have the deposited amount of SAND"
        );

        // Check if tokens are deposited in the pool
        (, , uint256[] memory balancesRaw, , ) = vault.getPoolTokenInfo(address(bufferPoolSand));
        assertEq(
            balancesRaw[0],
            bufferSandWrapped,
            "wSand BufferPool balance should have the deposited amount of wSand"
        );
        assertEq(
            balancesRaw[1],
            BUFFER_BASE_TOKENS,
            "wSand BufferPool balance should have the deposited amount of SAND"
        );

        // should mint correct amount of BPT tokens for buffer
        // Account for the precision loss
        assertApproxEqAbs(
            bufferPoolSand.balanceOf(lp),
            bptAmountOutSand,
            DELTA,
            "lp should have the BPT issued by the wSand BufferPool"
        );
        assertApproxEqAbs(
            bptAmountOutSand,
            2 * BUFFER_BASE_TOKENS,
            DELTA,
            string.concat(
                "The amount of BPT issued by the wSand BufferPool should be very ",
                "close to the sum of SAND+wSand (or 2 * SAND, as the buffer is balanced)"
            )
        );
    }

    function testDaiSmallRateWithMoreBase__Fuzz__Fork(uint256 assetsToTransfer) public {
        // assetsToTransfer will set the amount of assets that will unbalance the pool, and
        // varies from 0.001% of BUFFER_BASE_TOKENS to 95% of BUFFER_BASE_TOKENS
        assetsToTransfer = bound(assetsToTransfer, BUFFER_BASE_TOKENS / 100000, (95 * BUFFER_BASE_TOKENS) / 100);
        bufferPoolDai.unbalanceThePool(assetsToTransfer, SwapKind.EXACT_IN);

        // Check pool balances before rebalance to make sure it's unbalanced
        (uint256 daiBalanceBeforeRebalance, uint256 wDaiBalanceBeforeRebalance) = _checkBufferPoolBalance(
            vault,
            address(bufferPoolDai),
            wDAI_ADDRESS,
            BUFFER_BASE_TOKENS + assetsToTransfer,
            bufferDaiWrapped - wDAI.convertToShares(assetsToTransfer)
        );

        vm.prank(admin);
        bufferPoolDai.rebalance();

        // Check pool balances after rebalance to make sure it's balanced
        (uint256 daiBalanceAfterRebalance, uint256 wDaiBalanceAfterRebalance) = _checkBufferPoolBalance(
            vault,
            address(bufferPoolDai),
            wDAI_ADDRESS,
            BUFFER_BASE_TOKENS,
            wDAI.previewDeposit(BUFFER_BASE_TOKENS)
        );

        // Makes sure the rebalance rounding errors was in favour of the vault
        uint256 assetsInOneShare = wDAI.convertToAssets(1);
        assetsInOneShare = assetsInOneShare > 0 ? assetsInOneShare : 1;
        _checkBufferContractBalanceAfterRebalance(
            daiBalanceBeforeRebalance,
            daiBalanceAfterRebalance,
            wDaiBalanceBeforeRebalance,
            wDaiBalanceAfterRebalance,
            assetsInOneShare
        );
    }

    function testDaiSmallRateWithMoreWrapped__Fuzz__Fork(uint256 assetsToTransfer) public {
        // assetsToTransfer will set the amount of assets that will unbalance the pool, and
        // varies from 0.001% of BUFFER_BASE_TOKENS to 95% of BUFFER_BASE_TOKENS
        assetsToTransfer = bound(assetsToTransfer, BUFFER_BASE_TOKENS / 100000, (95 * BUFFER_BASE_TOKENS) / 100);
        bufferPoolDai.unbalanceThePool(assetsToTransfer, SwapKind.EXACT_OUT);

        // Check pool balances before rebalance to make sure it's unbalanced
        (uint256 daiBalanceBeforeRebalance, uint256 wDaiBalanceBeforeRebalance) = _checkBufferPoolBalance(
            vault,
            address(bufferPoolDai),
            wDAI_ADDRESS,
            BUFFER_BASE_TOKENS - assetsToTransfer,
            bufferDaiWrapped + wDAI.convertToShares(assetsToTransfer)
        );

        vm.prank(admin);
        bufferPoolDai.rebalance();

        // Check pool balances after rebalance to make sure it's balanced
        (uint256 daiBalanceAfterRebalance, uint256 wDaiBalanceAfterRebalance) = _checkBufferPoolBalance(
            vault,
            address(bufferPoolDai),
            wDAI_ADDRESS,
            BUFFER_BASE_TOKENS,
            wDAI.previewDeposit(BUFFER_BASE_TOKENS)
        );

        // Makes sure the rebalance rounding errors was in favour of the vault
        uint256 assetsInOneShare = wDAI.convertToAssets(1);
        assetsInOneShare = assetsInOneShare > 0 ? assetsInOneShare : 1;
        _checkBufferContractBalanceAfterRebalance(
            daiBalanceBeforeRebalance,
            daiBalanceAfterRebalance,
            wDaiBalanceBeforeRebalance,
            wDaiBalanceAfterRebalance,
            assetsInOneShare
        );
    }

    function testSandBigRateWithMoreBase__Fuzz__Fork(uint256 assetsToTransfer) public {
        // assetsToTransfer will set the amount of assets that will unbalance the pool, and
        // varies from 0.001% of BUFFER_BASE_TOKENS to 95% of BUFFER_BASE_TOKENS
        assetsToTransfer = bound(assetsToTransfer, BUFFER_BASE_TOKENS / 100000, (95 * BUFFER_BASE_TOKENS) / 100);
        bufferPoolSand.unbalanceThePool(assetsToTransfer, SwapKind.EXACT_IN);

        // Check pool balances before rebalance to make sure it's unbalanced
        (uint256 sandBalanceBeforeRebalance, uint256 wSandBalanceBeforeRebalance) = _checkBufferPoolBalance(
            vault,
            address(bufferPoolSand),
            wSAND_ADDRESS,
            BUFFER_BASE_TOKENS + assetsToTransfer,
            bufferSandWrapped - wSAND.convertToShares(assetsToTransfer)
        );

        vm.prank(admin);
        bufferPoolSand.rebalance();

        // Check pool balances after rebalance to make sure it's balanced
        (uint256 sandBalanceAfterRebalance, uint256 wSandBalanceAfterRebalance) = _checkBufferPoolBalance(
            vault,
            address(bufferPoolSand),
            wSAND_ADDRESS,
            BUFFER_BASE_TOKENS,
            wSAND.previewDeposit(BUFFER_BASE_TOKENS)
        );

        // Makes sure the rebalance rounding errors was in favour of the vault
        uint256 assetsInOneShare = wSAND.convertToAssets(1);
        assetsInOneShare = assetsInOneShare > 0 ? assetsInOneShare : 1;
        _checkBufferContractBalanceAfterRebalance(
            sandBalanceBeforeRebalance,
            sandBalanceAfterRebalance,
            wSandBalanceBeforeRebalance,
            wSandBalanceAfterRebalance,
            assetsInOneShare
        );
    }

    function testSandBigRateWithMoreWrapped__Fuzz__Fork(uint256 assetsToTransfer) public {
        // assetsToTransfer will set the amount of assets that will unbalance the pool, and
        // varies from 0.001% of BUFFER_BASE_TOKENS to 95% of BUFFER_BASE_TOKENS
        assetsToTransfer = bound(assetsToTransfer, BUFFER_BASE_TOKENS / 100000, (95 * BUFFER_BASE_TOKENS) / 100);
        bufferPoolSand.unbalanceThePool(assetsToTransfer, SwapKind.EXACT_OUT);

        // Check pool balances before rebalance to make sure it's unbalanced
        (uint256 sandBalanceBeforeRebalance, uint256 wSandBalanceBeforeRebalance) = _checkBufferPoolBalance(
            vault,
            address(bufferPoolSand),
            wSAND_ADDRESS,
            BUFFER_BASE_TOKENS - assetsToTransfer,
            bufferSandWrapped + wSAND.convertToShares(assetsToTransfer)
        );

        vm.prank(admin);
        bufferPoolSand.rebalance();

        // Check pool balances after rebalance to make sure it's balanced
        (uint256 sandBalanceAfterRebalance, uint256 wSandBalanceAfterRebalance) = _checkBufferPoolBalance(
            vault,
            address(bufferPoolSand),
            wSAND_ADDRESS,
            BUFFER_BASE_TOKENS,
            wSAND.previewDeposit(BUFFER_BASE_TOKENS)
        );

        // Makes sure the rebalance rounding errors was in favour of the vault
        uint256 assetsInOneShare = wSAND.convertToAssets(1);
        assetsInOneShare = assetsInOneShare > 0 ? assetsInOneShare : 1;
        _checkBufferContractBalanceAfterRebalance(
            sandBalanceBeforeRebalance,
            sandBalanceAfterRebalance,
            wSandBalanceBeforeRebalance,
            wSandBalanceAfterRebalance,
            assetsInOneShare
        );
    }

    function _createTokens() private {
        wDAI = new ERC4626TokenMock("Wrapped Dai", "wDAI", SMALL_AMOUNT, BIG_AMOUNT, IERC20(DAI_ADDRESS));
        wDAI_ADDRESS = address(wDAI);
        vm.label(wDAI_ADDRESS, "wDAI");

        wSAND = new ERC4626TokenMock("Wrapped Sand", "wSAND", BIG_AMOUNT, SMALL_AMOUNT, IERC20(SAND_ADDRESS));
        wSAND_ADDRESS = address(wSAND);
        vm.label(wSAND_ADDRESS, "wSAND");
    }

    function _createBuffer(IERC4626 wrappedToken) private returns (address) {
        return factory.createMocked(wrappedToken);
    }

    function _transferTokensFromDonorToUsers() private {
        address[] memory usersToTransfer = [address(lp)].toMemoryArray();

        for (uint256 index = 0; index < usersToTransfer.length; index++) {
            address userAddress = usersToTransfer[index];

            vm.startPrank(donor);
            daiMainnet.transfer(userAddress, 4 * BUFFER_BASE_TOKENS);
            sandMainnet.transfer(userAddress, 4 * BUFFER_BASE_TOKENS);
            vm.stopPrank();

            vm.startPrank(userAddress);
            daiMainnet.approve(address(vault), type(uint256).max);
            wDAI.approve(address(vault), type(uint256).max);
            daiMainnet.approve(address(wDAI), type(uint256).max);

            sandMainnet.approve(address(vault), type(uint256).max);
            wSAND.approve(address(vault), type(uint256).max);
            sandMainnet.approve(address(wSAND), type(uint256).max);
            vm.stopPrank();
        }
    }

    function _transferTokensFromDonorToBuffers() private {
        address[] memory buffersToTransfer = [address(bufferPoolDai), address(bufferPoolSand)].toMemoryArray();

        for (uint256 index = 0; index < buffersToTransfer.length; index++) {
            address bufferAddress = buffersToTransfer[index];

            vm.startPrank(donor);
            uint256 daiToConvert = wDAI.previewRedeem(1e18);
            daiMainnet.transfer(bufferAddress, daiToConvert + 1e18);

            uint256 sandToConvert = wSAND.previewDeposit(1e14);
            sandMainnet.transfer(bufferAddress, sandToConvert + 1e18);
            vm.stopPrank();

            vm.startPrank(bufferAddress);
            daiMainnet.approve(address(vault), type(uint256).max);
            wDAI.approve(address(vault), type(uint256).max);
            daiMainnet.approve(address(wDAI), type(uint256).max);
            wDAI.deposit(daiToConvert, bufferAddress);

            sandMainnet.approve(address(vault), type(uint256).max);
            wSAND.approve(address(vault), type(uint256).max);
            sandMainnet.approve(address(wSAND), type(uint256).max);
            wSAND.deposit(sandToConvert, bufferAddress);
            vm.stopPrank();
        }
    }

    function _setPermissions() private {
        authorizer.grantRole(bufferPoolDai.getActionId(IBufferPool.rebalance.selector), admin);
        authorizer.grantRole(bufferPoolSand.getActionId(IBufferPool.rebalance.selector), admin);
    }

    function _checkBufferPoolBalance(
        IVault vault,
        address bufferPool,
        address wrappedToken,
        uint256 balanceBaseRaw,
        uint256 balanceWrappedRaw
    ) private returns (uint256 contractBalanceBaseRaw, uint256 contractBalanceWrappedRaw) {
        IERC4626 wToken = IERC4626(wrappedToken);
        IERC20 baseToken = IERC20(wToken.asset());
        uint8 decimals = wToken.decimals();

        string memory baseTokenName = IERC20Metadata(address(baseToken)).name();
        string memory wrappedTokenName = IERC20Metadata(address(wToken)).name();

        // Check if the pool is unbalanced before
        (, , uint256[] memory originalBalances, , ) = vault.getPoolTokenInfo(bufferPool);
        assertApproxEqAbs(
            originalBalances[WRAPPED_TOKEN_INDEX],
            balanceWrappedRaw,
            10 ** (decimals / 2),
            string(
                abi.encodePacked(
                    string(abi.encodePacked(wrappedTokenName, " BufferPool balance of ")),
                    string(abi.encodePacked(wrappedTokenName, " does not match"))
                )
            )
        );
        assertApproxEqAbs(
            originalBalances[BASE_TOKEN_INDEX],
            balanceBaseRaw,
            10 ** (decimals / 2),
            string(
                abi.encodePacked(
                    string(abi.encodePacked(wrappedTokenName, " BufferPool balance of ")),
                    string(abi.encodePacked(baseTokenName, " does not match"))
                )
            )
        );

        contractBalanceBaseRaw = baseToken.balanceOf(bufferPool);
        contractBalanceWrappedRaw = wToken.balanceOf(bufferPool);
    }

    function _checkBufferContractBalanceAfterRebalance(
        uint256 baseBalanceBeforeRebalanceRaw,
        uint256 baseBalanceAfterRebalanceRaw,
        uint256 wrappedBalanceBeforeRebalanceRaw,
        uint256 wrappedBalanceAfterRebalanceRaw,
        uint256 assetsInOneShare
    ) private {
        // In the onSwap of ERC4626 buffer pool, depending on the direction of the swap, we add up to 2 assets
        // in the previewRedeem, to make sure the swap favors the vault, which counts as 2 extra tokens transferred
        // to the vault. The extra 1 token is related to rounding issues when depositing/withdrawing
        // (observed empirically). In total, we can miss by 3 shares.

        // Makes sure the base token balance didn't decrease in the pool contract by more than 3 units of
        // wrapped token (ERC4626 deposit sometimes leaves up to 3 shares converted to base assets tokens behind)
        assertApproxEqAbs(
            baseBalanceBeforeRebalanceRaw,
            baseBalanceAfterRebalanceRaw,
            3 * assetsInOneShare,
            "BufferPool contract should not lose more than 3 wrapped tokens (converted to base tokens) after rebalance"
        );
        // Makes sure the balance of wrapped tokens didn't change
        assertEq(
            wrappedBalanceBeforeRebalanceRaw,
            wrappedBalanceAfterRebalanceRaw,
            "The balance of wrapped tokens should not change in the buffer pool"
        );
    }
}
