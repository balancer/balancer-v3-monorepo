// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { IBufferPool } from "@balancer-labs/v3-interfaces/contracts/vault/IBufferPool.sol";
import { SwapKind } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ArrayHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/ArrayHelpers.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";
import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";

import { BaseVaultTest } from "vault/test/foundry/utils/BaseVaultTest.sol";

import { ERC4626BufferPoolFactoryMock } from "./utils/ERC4626BufferPoolFactoryMock.sol";
import { ERC4626BufferPoolMock } from "./utils/ERC4626BufferPoolMock.sol";
import { ERC4626TokenMock } from "./utils/ERC4626TokenMock.sol";

contract ERC4626RebalanceRateValidation is BaseVaultTest {
    using ArrayHelpers for *;
    using FixedPoint for uint256;

    ERC4626BufferPoolFactoryMock factory;
    ERC4626BufferPoolMock internal bufferPoolDai;
    ERC4626BufferPoolMock internal bufferPoolWsteth;

    ERC20TestToken mockedDai;
    IERC20 daiMainnet;
    IERC4626 wDAI;

    ERC20TestToken mockedWsteth;
    IERC20 wstethMainnet;
    IERC4626 wWstEth;

    address wDAI_ADDRESS;
    address wWSTETH_ADDRESS;

    uint256 constant BUFFER_BASE_TOKENS = 1e6 * 1e18;
    uint256 bufferDaiWrapped;
    uint256 bufferWstethWrapped;

    uint256 constant DELTA = 1e12;

    uint256 internal bptAmountOutDai;
    uint256 internal bptAmountOutWsteth;

    uint256 constant SMALL_AMOUNT = 3e6;
    uint256 constant BIG_AMOUNT = 1e12;

    function setUp() public virtual override {
        _createTokens();

        BaseVaultTest.setUp();
    }

    function createPool() internal override returns (address) {
        factory = new ERC4626BufferPoolFactoryMock(IVault(address(vault)), 365 days);

        bufferPoolDai = ERC4626BufferPoolMock(_createBuffer(wDAI));
        bufferPoolWsteth = ERC4626BufferPoolMock(_createBuffer(wWstEth));

        return address(bufferPoolDai);
    }

    function initPool() internal override {
        _giveTokensToLPs();
        // The swap calculation of the buffer is a bit imprecise to save gas,
        // so it needs to have some ERC20 to rebalance
        _giveTokensToBufferContracts();
        _setPermissions();

        vm.startPrank(lp);

        // Creating DAI Buffer
        bufferDaiWrapped = wDAI.convertToShares(BUFFER_BASE_TOKENS);
        wDAI.deposit(BUFFER_BASE_TOKENS, address(lp));

        uint256 wrappedTokenIdx = bufferPoolDai.getWrappedTokenIndex();
        uint256 baseTokenIdx = bufferPoolDai.getBaseTokenIndex();

        uint256[] memory amountsInDai = new uint256[](2);
        amountsInDai[wrappedTokenIdx] = bufferDaiWrapped;
        amountsInDai[baseTokenIdx] = BUFFER_BASE_TOKENS;

        IERC20[] memory tokens = InputHelpers.sortTokens([wDAI_ADDRESS, address(mockedDai)].toMemoryArray().asIERC20());

        bptAmountOutDai = _initPool(
            address(bufferPoolDai),
            amountsInDai,
            // Account for the precision loss
            BUFFER_BASE_TOKENS - DELTA - 1e6
        );

        // Creating WSTETH Buffer
        bufferWstethWrapped = wWstEth.convertToShares(BUFFER_BASE_TOKENS);
        wWstEth.deposit(BUFFER_BASE_TOKENS, address(lp));

        wrappedTokenIdx = bufferPoolWsteth.getWrappedTokenIndex();
        baseTokenIdx = bufferPoolWsteth.getBaseTokenIndex();

        uint256[] memory amountsInWsteth = new uint256[](2);
        amountsInWsteth[wrappedTokenIdx] = bufferWstethWrapped;
        amountsInWsteth[baseTokenIdx] = BUFFER_BASE_TOKENS;

        tokens[wrappedTokenIdx] = IERC20(wWSTETH_ADDRESS);
        tokens[baseTokenIdx] = IERC20(address(mockedWsteth));

        bptAmountOutWsteth = _initPool(
            address(bufferPoolWsteth),
            amountsInWsteth,
            // Account for the precision loss
            BUFFER_BASE_TOKENS - DELTA - 1e6
        );
        vm.stopPrank();
    }

    function testInitializeDai() public {
        // Tokens are stored in the Vault
        assertEq(wDAI.balanceOf(address(vault)), bufferDaiWrapped, "Vault should have the deposited amount of wDai");
        assertEq(
            daiMainnet.balanceOf(address(vault)),
            BUFFER_BASE_TOKENS,
            "Vault should have the deposited amount of DAI"
        );

        // Check if tokens are deposited in the pool
        (, , uint256[] memory actualBalances, , ) = vault.getPoolTokenInfo(address(bufferPoolDai));
        uint256 wrappedTokenIdx = bufferPoolDai.getWrappedTokenIndex();
        uint256 baseTokenIdx = bufferPoolDai.getBaseTokenIndex();

        assertEq(
            actualBalances[wrappedTokenIdx],
            bufferDaiWrapped,
            "wDai BufferPool balance should have the deposited amount of wDai"
        );
        assertEq(
            actualBalances[baseTokenIdx],
            BUFFER_BASE_TOKENS,
            "wDai BufferPool balance should have the deposited amount of DAI"
        );

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

    function testInitializeWsteth() public {
        // Tokens are stored in the Vault
        assertEq(
            wWstEth.balanceOf(address(vault)),
            bufferWstethWrapped,
            "Vault should have the deposited amount of wWsteth"
        );
        assertEq(
            wstethMainnet.balanceOf(address(vault)),
            BUFFER_BASE_TOKENS,
            "Vault should have the deposited amount of WSTETH"
        );

        // Check if tokens are deposited in the pool
        (, , uint256[] memory actualBalances, , ) = vault.getPoolTokenInfo(address(bufferPoolWsteth));
        uint256 wrappedTokenIdx = bufferPoolWsteth.getWrappedTokenIndex();
        uint256 baseTokenIdx = bufferPoolWsteth.getBaseTokenIndex();

        assertEq(
            actualBalances[wrappedTokenIdx],
            bufferWstethWrapped,
            "wWsteth BufferPool balance should have the deposited amount of wWsteth"
        );
        assertEq(
            actualBalances[baseTokenIdx],
            BUFFER_BASE_TOKENS,
            "wWsteth BufferPool balance should have the deposited amount of WSTETH"
        );

        // should mint correct amount of BPT tokens for buffer
        // Account for the precision loss
        assertApproxEqAbs(
            bufferPoolWsteth.balanceOf(lp),
            bptAmountOutWsteth,
            DELTA,
            "lp should have the BPT issued by the wWsteth BufferPool"
        );
        assertApproxEqAbs(
            bptAmountOutWsteth,
            2 * BUFFER_BASE_TOKENS,
            DELTA,
            string.concat(
                "The amount of BPT issued by the wWsteth BufferPool should be very ",
                "close to the sum of WSTETH+wWsteth (or 2 * WSTETH, as the buffer is balanced)"
            )
        );
    }

    function testDaiSmallRateWithMoreBase__Fuzz(uint256 assetsToTransfer) public {
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

    function testDaiSmallRateWithMoreWrapped__Fuzz(uint256 assetsToTransfer) public {
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

    function testWstethBigRateWithMoreBase__Fuzz(uint256 assetsToTransfer) public {
        // assetsToTransfer will set the amount of assets that will unbalance the pool, and
        // varies from 0.001% of BUFFER_BASE_TOKENS to 95% of BUFFER_BASE_TOKENS
        assetsToTransfer = bound(assetsToTransfer, BUFFER_BASE_TOKENS / 100000, (95 * BUFFER_BASE_TOKENS) / 100);
        bufferPoolWsteth.unbalanceThePool(assetsToTransfer, SwapKind.EXACT_IN);

        // Check pool balances before rebalance to make sure it's unbalanced
        (uint256 wstethBalanceBeforeRebalance, uint256 wWstethBalanceBeforeRebalance) = _checkBufferPoolBalance(
            vault,
            address(bufferPoolWsteth),
            wWSTETH_ADDRESS,
            BUFFER_BASE_TOKENS + assetsToTransfer,
            bufferWstethWrapped - wWstEth.convertToShares(assetsToTransfer)
        );

        vm.prank(admin);
        bufferPoolWsteth.rebalance();

        // Check pool balances after rebalance to make sure it's balanced
        (uint256 wstethBalanceAfterRebalance, uint256 wWstethBalanceAfterRebalance) = _checkBufferPoolBalance(
            vault,
            address(bufferPoolWsteth),
            wWSTETH_ADDRESS,
            BUFFER_BASE_TOKENS,
            wWstEth.previewDeposit(BUFFER_BASE_TOKENS)
        );

        // Makes sure the rebalance rounding errors was in favour of the vault
        uint256 assetsInOneShare = wWstEth.convertToAssets(1);
        assetsInOneShare = assetsInOneShare > 0 ? assetsInOneShare : 1;
        _checkBufferContractBalanceAfterRebalance(
            wstethBalanceBeforeRebalance,
            wstethBalanceAfterRebalance,
            wWstethBalanceBeforeRebalance,
            wWstethBalanceAfterRebalance,
            assetsInOneShare
        );
    }

    function testWstethBigRateWithMoreWrapped__Fuzz(uint256 assetsToTransfer) public {
        // assetsToTransfer will set the amount of assets that will unbalance the pool, and
        // varies from 0.001% of BUFFER_BASE_TOKENS to 95% of BUFFER_BASE_TOKENS
        assetsToTransfer = bound(assetsToTransfer, BUFFER_BASE_TOKENS / 100000, (95 * BUFFER_BASE_TOKENS) / 100);
        bufferPoolWsteth.unbalanceThePool(assetsToTransfer, SwapKind.EXACT_OUT);

        // Check pool balances before rebalance to make sure it's unbalanced
        (uint256 wstethBalanceBeforeRebalance, uint256 wWstethBalanceBeforeRebalance) = _checkBufferPoolBalance(
            vault,
            address(bufferPoolWsteth),
            wWSTETH_ADDRESS,
            BUFFER_BASE_TOKENS - assetsToTransfer,
            bufferWstethWrapped + wWstEth.convertToShares(assetsToTransfer)
        );

        vm.prank(admin);
        bufferPoolWsteth.rebalance();

        // Check pool balances after rebalance to make sure it's balanced
        (uint256 wstethBalanceAfterRebalance, uint256 wWstethBalanceAfterRebalance) = _checkBufferPoolBalance(
            vault,
            address(bufferPoolWsteth),
            wWSTETH_ADDRESS,
            BUFFER_BASE_TOKENS,
            wWstEth.previewDeposit(BUFFER_BASE_TOKENS)
        );

        // Makes sure the rebalance rounding errors was in favour of the vault
        uint256 assetsInOneShare = wWstEth.convertToAssets(1);
        assetsInOneShare = assetsInOneShare > 0 ? assetsInOneShare : 1;
        _checkBufferContractBalanceAfterRebalance(
            wstethBalanceBeforeRebalance,
            wstethBalanceAfterRebalance,
            wWstethBalanceBeforeRebalance,
            wWstethBalanceAfterRebalance,
            assetsInOneShare
        );
    }

    function _createTokens() private {
        mockedDai = createERC20("DAI", 18);
        daiMainnet = IERC20(address(mockedDai));

        mockedWsteth = createERC20("WSTETH", 18);
        wstethMainnet = IERC20(address(mockedWsteth));

        wDAI = new ERC4626TokenMock("Wrapped Dai", "wDAI", SMALL_AMOUNT, BIG_AMOUNT, daiMainnet);
        wDAI_ADDRESS = address(wDAI);
        vm.label(wDAI_ADDRESS, "wDAI");

        wWstEth = new ERC4626TokenMock("Wrapped WSTETH", "wWSTETH", BIG_AMOUNT, SMALL_AMOUNT, wstethMainnet);
        wWSTETH_ADDRESS = address(wWstEth);
        vm.label(wWSTETH_ADDRESS, "wWSTETH");
    }

    function _createBuffer(IERC4626 wrappedToken) private returns (address) {
        return factory.createMocked(wrappedToken);
    }

    function _giveTokensToLPs() private {
        address[] memory usersToTransfer = [address(lp)].toMemoryArray();

        for (uint256 index = 0; index < usersToTransfer.length; index++) {
            address userAddress = usersToTransfer[index];

            mockedDai.mint(userAddress, 4 * BUFFER_BASE_TOKENS);
            mockedWsteth.mint(userAddress, 4 * BUFFER_BASE_TOKENS);

            vm.startPrank(userAddress);
            daiMainnet.approve(address(permit2), MAX_UINT256);
            permit2.approve(address(daiMainnet), address(router), type(uint160).max, type(uint48).max);
            wDAI.approve(address(permit2), MAX_UINT256);
            permit2.approve(address(wDAI), address(router), type(uint160).max, type(uint48).max);
            daiMainnet.approve(address(wDAI), MAX_UINT256);

            wstethMainnet.approve(address(permit2), MAX_UINT256);
            permit2.approve(address(wstethMainnet), address(router), type(uint160).max, type(uint48).max);
            wstethMainnet.approve(address(wWstEth), MAX_UINT256);
            wWstEth.approve(address(permit2), MAX_UINT256);
            permit2.approve(address(wWstEth), address(router), type(uint160).max, type(uint48).max);
            vm.stopPrank();
        }
    }

    function _giveTokensToBufferContracts() private {
        address[] memory buffersToTransfer = [address(bufferPoolDai), address(bufferPoolWsteth)].toMemoryArray();

        for (uint256 index = 0; index < buffersToTransfer.length; index++) {
            address bufferAddress = buffersToTransfer[index];

            uint256 daiToConvert = wDAI.previewRedeem(1e18);
            mockedDai.mint(bufferAddress, daiToConvert + 1e18);

            uint256 wstethToConvert = wWstEth.previewDeposit(1e14);
            mockedWsteth.mint(bufferAddress, wstethToConvert + 1e18);

            vm.startPrank(bufferAddress);
            daiMainnet.approve(address(wDAI), daiToConvert);
            wDAI.deposit(daiToConvert, bufferAddress);

            wstethMainnet.approve(address(wWstEth), wstethToConvert);
            wWstEth.deposit(wstethToConvert, bufferAddress);
            vm.stopPrank();
        }
    }

    function _setPermissions() private {
        authorizer.grantRole(bufferPoolDai.getActionId(IBufferPool.rebalance.selector), admin);
        authorizer.grantRole(bufferPoolWsteth.getActionId(IBufferPool.rebalance.selector), admin);
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

        (uint256 wrappedTokenIdx, uint256 baseTokenIdx) = getSortedIndexes(wrappedToken, address(baseToken));

        string memory baseTokenName = IERC20Metadata(address(baseToken)).name();
        string memory wrappedTokenName = IERC20Metadata(address(wToken)).name();

        // Check if the pool is unbalanced before
        (, , uint256[] memory actualBalances, , ) = vault.getPoolTokenInfo(bufferPool);
        assertApproxEqAbs(
            actualBalances[wrappedTokenIdx],
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
            actualBalances[baseTokenIdx],
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
        uint256 wrappedBalanceAfterRebalance,
        uint256 assetsInOneShare
    ) private {
        // In the onSwap of ERC4626 buffer pool, depending on the direction of the swap, we add up to 2 assets
        // in the previewRedeem, to make sure the swap favors the vault, which counts as 2 extra tokens transferred
        // to the vault. The extra 1 token is related to rounding issues when depositing/withdrawing
        // (observed empirically). In total, we can miss by 3 shares.

        // Makes sure the base token balance didn't decrease in the pool contract by more than 3 units of
        // wrapped token (ERC4626 deposit sometimes leaves up to 3 shares converted to base assets tokens behind)
        assertApproxEqAbs(
            baseBalanceBeforeRebalance,
            baseBalanceAfterRebalance,
            3 * assetsInOneShare,
            "BufferPool contract should not lose more than 3 wrapped tokens (converted to base tokens) after rebalance"
        );
        // Makes sure the balance of wrapped tokens didn't change
        assertEq(
            wrappedBalanceBeforeRebalance,
            wrappedBalanceAfterRebalance,
            "The balance of wrapped tokens should not change in the buffer pool"
        );
    }
}
