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

contract ERC4626RebalanceValidation is BaseVaultTest {
    using ArrayHelpers for *;
    using FixedPoint for uint256;

    uint8 immutable WRAPPED_TOKEN_INDEX = 0;
    uint8 immutable BASE_TOKEN_INDEX = 1;

    ERC4626BufferPoolFactoryMock factory;
    ERC4626BufferPoolMock internal bufferPoolUsdc;
    ERC4626BufferPoolMock internal bufferPoolDai;

    IERC20 daiMainnet;
    IERC4626 waDAI;
    IERC20 usdcMainnet;
    IERC4626 waUSDC;

    // Using older block number because convertToAssets function is bricked in the new version of the aToken wrapper
    uint256 constant BLOCK_NUMBER = 17965150;

    address constant aDAI_ADDRESS = 0x098256c06ab24F5655C5506A6488781BD711c14b;
    address constant aUSDC_ADDRESS = 0x57d20c946A7A3812a7225B881CdcD8431D23431C;
    address constant DAI_ADDRESS = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant USDC_ADDRESS = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    // Owner of DAI and USDC in Mainnet
    address constant DONOR_WALLET_ADDRESS = 0x47ac0Fb4F2D84898e4D9E7b4DaB3C24507a6D503;

    address payable donor;

    uint256 constant BUFFER_DAI_BASE = 1e6 * 1e18;
    uint256 bufferDaiWrapped;

    uint256 constant BUFFER_USDC_BASE = 1e6 * 1e6;
    uint256 bufferUsdcWrapped;

    uint256 constant DELTA = 1e12;

    uint256 internal bptAmountOutBase;
    uint256 internal bptAmountOutWrapped;

    function setUp() public virtual override {
        vm.createSelectFork({ blockNumber: BLOCK_NUMBER, urlOrAlias: "mainnet" });

        donor = payable(DONOR_WALLET_ADDRESS);
        vm.label(donor, "TokenDonor");

        _setupTokens();

        BaseVaultTest.setUp();
    }

    function createPool() internal override returns (address) {
        factory = new ERC4626BufferPoolFactoryMock(IVault(address(vault)), 365 days);
        authorizer.grantRole(vault.getActionId(IVaultAdmin.registerBufferPoolFactory.selector), alice);
        vm.prank(alice);
        vault.registerBufferPoolFactory(address(factory));

        bufferPoolDai = ERC4626BufferPoolMock(_createBuffer(waDAI));
        bufferPoolUsdc = ERC4626BufferPoolMock(_createBuffer(waUSDC));

        return address(bufferPoolDai);
    }

    function initPool() internal override {
        _transferTokensFromDonorToUsers();
        // The swap calculation of the buffer is a bit imprecise to save gas,
        // so it needs to have some ERC20 to rebalance
        _transferTokensFromDonorToBuffers();
        _setPermissions();

        vm.startPrank(lp);

        // Creating aDAI Buffer
        bufferDaiWrapped = waDAI.convertToShares(BUFFER_DAI_BASE);
        waDAI.deposit(BUFFER_DAI_BASE, address(lp));
        uint256[] memory amountsInMoreBase = [uint256(bufferDaiWrapped), uint256(BUFFER_DAI_BASE)].toMemoryArray();
        bptAmountOutBase = router.initialize(
            address(bufferPoolDai),
            [aDAI_ADDRESS, DAI_ADDRESS].toMemoryArray().asIERC20(),
            amountsInMoreBase,
            // Account for the precision loss
            BUFFER_DAI_BASE - DELTA - 1e6,
            false,
            bytes("")
        );

        // Creating aUSDC Buffer
        bufferUsdcWrapped = waUSDC.convertToShares(BUFFER_USDC_BASE);
        waUSDC.deposit(BUFFER_USDC_BASE, address(lp));
        uint256[] memory amountsInMoreWrapped = [uint256(bufferUsdcWrapped), uint256(BUFFER_USDC_BASE)].toMemoryArray();
        bptAmountOutWrapped = router.initialize(
            address(bufferPoolUsdc),
            [aUSDC_ADDRESS, USDC_ADDRESS].toMemoryArray().asIERC20(),
            amountsInMoreWrapped,
            // Account for the precision loss
            BUFFER_USDC_BASE - 1e6,
            false,
            bytes("")
        );
        vm.stopPrank();
    }

    function testInitialize__Fork() public {
        // Tokens are stored in the Vault
        assertEq(waDAI.balanceOf(address(vault)), bufferDaiWrapped, "Vault should have the deposited amount of aDAI");
        assertEq(
            daiMainnet.balanceOf(address(vault)),
            BUFFER_DAI_BASE,
            "Vault should have the deposited amount of DAI"
        );
        assertEq(
            waUSDC.balanceOf(address(vault)),
            bufferUsdcWrapped,
            "Vault should have the deposited amount of aUSDC"
        );
        assertEq(
            usdcMainnet.balanceOf(address(vault)),
            BUFFER_USDC_BASE,
            "Vault should have the deposited amount of USDC"
        );

        // Tokens are deposited to the pool with more base
        (, , uint256[] memory moreBaseBalances, , ) = vault.getPoolTokenInfo(address(bufferPoolDai));
        assertEq(
            moreBaseBalances[WRAPPED_TOKEN_INDEX],
            bufferDaiWrapped,
            "aDai BufferPool balance should have the deposited amount of aDAI"
        );
        assertEq(
            moreBaseBalances[BASE_TOKEN_INDEX],
            BUFFER_DAI_BASE,
            "aDai BufferPool balance should have the deposited amount of DAI"
        );

        // Tokens are deposited to the pool with more wrapped
        (, , uint256[] memory moreWrappedBalances, , ) = vault.getPoolTokenInfo(address(bufferPoolUsdc));
        assertEq(
            moreWrappedBalances[WRAPPED_TOKEN_INDEX],
            bufferUsdcWrapped,
            "aUSDC BufferPool balance should have the deposited amount of aUSDC"
        );
        assertEq(
            moreWrappedBalances[BASE_TOKEN_INDEX],
            BUFFER_USDC_BASE,
            "aUSDC BufferPool balance should have the deposited amount of USDC"
        );

        // should mint correct amount of BPT tokens for buffer with more base
        // Account for the precision loss
        assertApproxEqAbs(
            bufferPoolDai.balanceOf(lp),
            bptAmountOutBase,
            DELTA,
            "lp should have the BPT issued by the aDAI BufferPool"
        );
        assertApproxEqAbs(
            bptAmountOutBase,
            2 * BUFFER_DAI_BASE,
            DELTA,
            "The amount of issued BPT of aDAI BufferPool should be very close from the amount of deposited DAI"
        );

        // should mint correct amount of BPT tokens for buffer with more wrapped
        // Account for the precision loss
        assertApproxEqAbs(
            bufferPoolUsdc.balanceOf(lp),
            bptAmountOutWrapped,
            DELTA,
            "lp should have the BPT issued by the aUSDC BufferPool"
        );
        assertApproxEqAbs(
            bptAmountOutWrapped,
            2 * BUFFER_USDC_BASE * 1e12,
            DELTA,
            "The amount of issued BPT of aUSDC BufferPool should be very close from the amount of deposited USDC"
        );
    }

    function testRebalanceForDaiWithMoreBase__Fuzz__Fork(uint256 assetsToTransfer) public {
        // assetsToTransfer will set the amount of assets that will unbalance the pool, and
        // varies from 0.001% of BUFFER_DAI_BASE to 95% of BUFFER_DAI_BASE
        assetsToTransfer = bound(assetsToTransfer, BUFFER_DAI_BASE / 100000, (95 * BUFFER_DAI_BASE) / 100);
        bufferPoolDai.unbalanceThePool(assetsToTransfer, SwapKind.EXACT_IN);

        (uint256 daiBalanceBeforeRebalance, uint256 aDaiBalanceBeforeRebalance) = _checkBufferPoolBalance(
            vault,
            address(bufferPoolDai),
            aDAI_ADDRESS,
            BUFFER_DAI_BASE + assetsToTransfer,
            bufferDaiWrapped - waDAI.convertToShares(assetsToTransfer)
        );

        vm.prank(admin);
        bufferPoolDai.rebalance();

        // Check if the pool is balanced after
        (uint256 daiBalanceAfterRebalance, uint256 aDaiBalanceAfterRebalance) = _checkBufferPoolBalance(
            vault,
            address(bufferPoolDai),
            aDAI_ADDRESS,
            BUFFER_DAI_BASE,
            waDAI.previewDeposit(BUFFER_DAI_BASE)
        );

        // Makes sure the rebalance rounding errors was in favour of the vault
        _checkBufferContractBalanceAfterRebalance(
            daiBalanceBeforeRebalance,
            daiBalanceAfterRebalance,
            aDaiBalanceBeforeRebalance,
            aDaiBalanceAfterRebalance
        );
    }

    function testRebalanceForDaiWithMoreWrapped__Fuzz__Fork(uint256 assetsToTransfer) public {
        // assetsToTransfer will set the amount of assets that will unbalance the pool, and
        // varies from 0.001% of BUFFER_DAI_BASE to 95% of BUFFER_DAI_BASE
        assetsToTransfer = bound(assetsToTransfer, BUFFER_DAI_BASE / 100000, (95 * BUFFER_DAI_BASE) / 100);
        bufferPoolDai.unbalanceThePool(assetsToTransfer, SwapKind.EXACT_OUT);

        (uint256 daiBalanceBeforeRebalance, uint256 aDaiBalanceBeforeRebalance) = _checkBufferPoolBalance(
            vault,
            address(bufferPoolDai),
            aDAI_ADDRESS,
            BUFFER_DAI_BASE - assetsToTransfer,
            bufferDaiWrapped + waDAI.convertToShares(assetsToTransfer)
        );

        vm.prank(admin);
        bufferPoolDai.rebalance();

        // Check if the pool is balanced after
        (uint256 daiBalanceAfterRebalance, uint256 aDaiBalanceAfterRebalance) = _checkBufferPoolBalance(
            vault,
            address(bufferPoolDai),
            aDAI_ADDRESS,
            BUFFER_DAI_BASE,
            waDAI.previewDeposit(BUFFER_DAI_BASE)
        );

        // Makes sure the rebalance rounding errors was in favour of the vault
        _checkBufferContractBalanceAfterRebalance(
            daiBalanceBeforeRebalance,
            daiBalanceAfterRebalance,
            aDaiBalanceBeforeRebalance,
            aDaiBalanceAfterRebalance
        );
    }

    function testRebalanceForUsdcWithMoreBase__Fuzz__Fork(uint256 assetsToTransfer) public {
        // assetsToTransfer will set the amount of assets that will unbalance the pool, and
        // varies from 0.001% of BUFFER_USDC_BASE to 95% of BUFFER_USDC_BASE
        assetsToTransfer = bound(assetsToTransfer, BUFFER_USDC_BASE / 100000, (95 * BUFFER_USDC_BASE) / 100);
        bufferPoolUsdc.unbalanceThePool(assetsToTransfer, SwapKind.EXACT_IN);

        (uint256 usdcBalanceBeforeRebalance, uint256 ausdcBalanceBeforeRebalance) = _checkBufferPoolBalance(
            vault,
            address(bufferPoolUsdc),
            aUSDC_ADDRESS,
            BUFFER_USDC_BASE + assetsToTransfer,
            bufferUsdcWrapped - waUSDC.convertToShares(assetsToTransfer)
        );

        vm.prank(admin);
        bufferPoolUsdc.rebalance();

        // Check if the pool is balanced after
        (uint256 usdcBalanceAfterRebalance, uint256 ausdcBalanceAfterRebalance) = _checkBufferPoolBalance(
            vault,
            address(bufferPoolUsdc),
            aUSDC_ADDRESS,
            BUFFER_USDC_BASE,
            waUSDC.previewDeposit(BUFFER_USDC_BASE)
        );

        // Makes sure the rebalance rounding errors was in favour of the vault
        _checkBufferContractBalanceAfterRebalance(
            usdcBalanceBeforeRebalance,
            usdcBalanceAfterRebalance,
            ausdcBalanceBeforeRebalance,
            ausdcBalanceAfterRebalance
        );
    }

    function testRebalanceForUsdcWithMoreWrapped__Fuzz__Fork(uint256 assetsToTransfer) public {
        // assetsToTransfer will set the amount of assets that will unbalance the pool, and
        // varies from 0.001% of BUFFER_USDC_BASE to 95% of BUFFER_USDC_BASE
        assetsToTransfer = bound(assetsToTransfer, BUFFER_USDC_BASE / 100000, (95 * BUFFER_USDC_BASE) / 100);
        bufferPoolUsdc.unbalanceThePool(assetsToTransfer, SwapKind.EXACT_OUT);

        (uint256 usdcBalanceBeforeRebalance, uint256 ausdcBalanceBeforeRebalance) = _checkBufferPoolBalance(
            vault,
            address(bufferPoolUsdc),
            aUSDC_ADDRESS,
            BUFFER_USDC_BASE - assetsToTransfer,
            bufferUsdcWrapped + waUSDC.convertToShares(assetsToTransfer)
        );

        vm.prank(admin);
        bufferPoolUsdc.rebalance();

        // Check if the pool is balanced after
        (uint256 usdcBalanceAfterRebalance, uint256 ausdcBalanceAfterRebalance) = _checkBufferPoolBalance(
            vault,
            address(bufferPoolUsdc),
            aUSDC_ADDRESS,
            BUFFER_USDC_BASE,
            waUSDC.previewDeposit(BUFFER_USDC_BASE)
        );

        // Makes sure the rebalance rounding errors was in favour of the vault
        _checkBufferContractBalanceAfterRebalance(
            usdcBalanceBeforeRebalance,
            usdcBalanceAfterRebalance,
            ausdcBalanceBeforeRebalance,
            ausdcBalanceAfterRebalance
        );
    }

    function _createBuffer(IERC4626 wrappedToken) private returns (address) {
        return factory.createMocked(wrappedToken);
    }

    function _transferTokensFromDonorToUsers() private {
        address[] memory usersToTransfer = [address(lp)].toMemoryArray();

        for (uint256 index = 0; index < usersToTransfer.length; index++) {
            address userAddress = usersToTransfer[index];

            vm.startPrank(donor);
            daiMainnet.transfer(userAddress, 4 * BUFFER_DAI_BASE);
            usdcMainnet.transfer(userAddress, 4 * BUFFER_USDC_BASE);
            vm.stopPrank();

            vm.startPrank(userAddress);
            daiMainnet.approve(address(vault), type(uint256).max);
            waDAI.approve(address(vault), type(uint256).max);
            daiMainnet.approve(address(waDAI), type(uint256).max);

            usdcMainnet.approve(address(vault), type(uint256).max);
            waUSDC.approve(address(vault), type(uint256).max);
            usdcMainnet.approve(address(waUSDC), type(uint256).max);
            vm.stopPrank();
        }
    }

    function _transferTokensFromDonorToBuffers() private {
        address[] memory buffersToTransfer = [address(bufferPoolUsdc), address(bufferPoolDai)].toMemoryArray();

        for (uint256 index = 0; index < buffersToTransfer.length; index++) {
            address bufferAddress = buffersToTransfer[index];

            vm.startPrank(donor);
            uint256 daiToConvert = waDAI.previewRedeem(1e18);
            daiMainnet.transfer(bufferAddress, daiToConvert + 1e18);
            uint256 usdcToConvert = waUSDC.previewRedeem(1e6);
            usdcMainnet.transfer(bufferAddress, usdcToConvert + 1e6);
            vm.stopPrank();

            vm.startPrank(bufferAddress);
            daiMainnet.approve(address(waDAI), daiToConvert);
            waDAI.deposit(daiToConvert, bufferAddress);

            usdcMainnet.approve(address(waUSDC), usdcToConvert);
            waUSDC.deposit(usdcToConvert, bufferAddress);
            vm.stopPrank();
        }
    }

    function _setPermissions() private {
        authorizer.grantRole(bufferPoolDai.getActionId(IBufferPool.rebalance.selector), admin);
        authorizer.grantRole(bufferPoolUsdc.getActionId(IBufferPool.rebalance.selector), admin);
    }

    function _setupTokens() private {
        daiMainnet = IERC20(DAI_ADDRESS);
        waDAI = IERC4626(aDAI_ADDRESS);
        vm.label(DAI_ADDRESS, "DAI");
        vm.label(aDAI_ADDRESS, "aDAI");

        usdcMainnet = IERC20(USDC_ADDRESS);
        waUSDC = IERC4626(aUSDC_ADDRESS);
        vm.label(USDC_ADDRESS, "USDC");
        vm.label(aUSDC_ADDRESS, "aUSDC");
    }

    function _checkBufferPoolBalance(
        IVault vault,
        address bufferPool,
        address wrappedToken,
        uint256 expectedBaseBalance,
        uint256 expectedWrappedBalance
    ) private returns (uint256 contractBaseBalance, uint256 contractWrappedBalance) {
        IERC4626 wToken = IERC4626(wrappedToken);
        IERC20 baseToken = IERC20(wToken.asset());
        uint8 decimals = wToken.decimals();

        string memory baseTokenName = IERC20Metadata(address(baseToken)).name();
        string memory wrappedTokenName = IERC20Metadata(address(wToken)).name();

        // Check if the pool is unbalanced before
        (, , uint256[] memory originalBalances, , ) = vault.getPoolTokenInfo(bufferPool);
        assertApproxEqAbs(
            originalBalances[WRAPPED_TOKEN_INDEX],
            expectedWrappedBalance,
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
            expectedBaseBalance,
            10 ** (decimals / 2),
            string(
                abi.encodePacked(
                    string(abi.encodePacked(wrappedTokenName, " BufferPool balance of ")),
                    string(abi.encodePacked(baseTokenName, " does not match"))
                )
            )
        );

        contractBaseBalance = baseToken.balanceOf(bufferPool);
        contractWrappedBalance = wToken.balanceOf(bufferPool);
    }

    function _checkBufferContractBalanceAfterRebalance(
        uint256 baseBalanceBeforeRebalance,
        uint256 baseBalanceAfterRebalance,
        uint256 wrappedBalanceBeforeRebalance,
        uint256 wrappedBalanceAfterRebalance
    ) private {
        // Makes sure the base token balance didn't decrease in the pool contract by more than 5 units
        // (ERC4626 deposit sometimes leave up to 5 tokens behind)
        assertApproxEqAbs(
            baseBalanceBeforeRebalance - baseBalanceAfterRebalance,
            0,
            5,
            "BufferPool contract should not lose more than 5 base tokens after rebalance"
        );
        // Makes sure the balance of wrapped tokens don't change
        assertEq(
            wrappedBalanceBeforeRebalance,
            wrappedBalanceAfterRebalance,
            "The balance of wrapped tokens should not change in the buffer pool"
        );
    }
}
