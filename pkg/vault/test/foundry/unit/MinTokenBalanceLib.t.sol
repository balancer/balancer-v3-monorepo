// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { TokenConfig } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";

import { ERC20TestToken } from "@balancer-labs/v3-solidity-utils/contracts/test/ERC20TestToken.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";

import { MinTokenBalanceLibMock } from "../../../contracts/test/MinTokenBalanceLibMock.sol";
import { MinTokenBalanceLib } from "../../../contracts/lib/MinTokenBalanceLib.sol";
import { VaultContractsDeployer } from "../utils/VaultContractsDeployer.sol";

contract MinTokenBalanceLibTest is VaultContractsDeployer {
    MinTokenBalanceLibMock tokenBalanceLibMock;

    ERC20TestToken internal dai;
    ERC20TestToken internal usdc;
    ERC20TestToken internal d13;
    ERC20TestToken internal d12;
    ERC20TestToken internal d0;

    IERC20[] internal testTokens;

    function setUp() public {
        tokenBalanceLibMock = deployMinTokenBalanceLibMock();

        dai = createERC20("DAI", 18);
        usdc = createERC20("USDC", 6);
        d13 = createERC20("D13", 13);
        d12 = createERC20("D12", 12);
        d0 = createERC20("D0", 0);

        testTokens = new IERC20[](5);
        testTokens[0] = dai;
        testTokens[1] = usdc;
        testTokens[2] = d13;
        testTokens[3] = d12;
        testTokens[4] = d0;
    }

    function testValidationLengthMatch() public {
        TokenConfig[] memory tokenConfig = buildTokenConfig(testTokens);
        uint256[] memory shortArray = new uint256[](3);

        vm.expectRevert(InputHelpers.InputLengthMismatch.selector);
        tokenBalanceLibMock.validateMinimumTokenBalances(tokenConfig, shortArray);
    }

    function testValidationInvalidMinBalance() public {
        TokenConfig[] memory tokenConfig = buildTokenConfig(testTokens);
        uint256[] memory zeroMinimums = new uint256[](5);
        uint256 absoluteMin = MinTokenBalanceLib.POOL_MINIMUM_TOTAL_SUPPLY / tokenConfig.length;

        vm.expectRevert(
            abi.encodeWithSelector(MinTokenBalanceLib.InvalidMinTokenBalance.selector, address(dai), 0, absoluteMin)
        );
        tokenBalanceLibMock.validateMinimumTokenBalances(tokenConfig, zeroMinimums);
    }

    function testValidationNoUserMinimums() public view {
        TokenConfig[] memory tokenConfig = buildTokenConfig(testTokens);
        uint256[] memory emptyArray = new uint256[](0);

        uint256 defaultMinBalance = MinTokenBalanceLib.POOL_MINIMUM_TOTAL_SUPPLY / tokenConfig.length;
        uint256 expectedMinBalance;

        uint256[] memory finalMinTokenBalances = tokenBalanceLibMock.validateMinimumTokenBalances(
            tokenConfig,
            emptyArray
        );
        for (uint256 i = 0; i < tokenConfig.length; ++i) {
            address token = address(tokenConfig[i].token);
            uint256 tokenDecimals = IERC20Metadata(token).decimals();

            if (tokenDecimals > 12) {
                expectedMinBalance = defaultMinBalance;
            } else {
                expectedMinBalance = 10 ** (18 - tokenDecimals);
            }

            assertEq(finalMinTokenBalances[i], expectedMinBalance, "Wrong minimum balance");
        }
    }

    function buildTokenConfig(IERC20[] memory tokens) internal pure returns (TokenConfig[] memory config) {
        uint256 numTokens = tokens.length;

        config = new TokenConfig[](numTokens);

        for (uint256 i = 0; i < numTokens; ++i) {
            config[i].token = tokens[i];
        }
    }

    function createERC20(string memory name, uint8 decimals) internal returns (ERC20TestToken token) {
        token = new ERC20TestToken(name, name, decimals);
        vm.label(address(token), name);
    }
}
