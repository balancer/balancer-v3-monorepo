// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

contract ProtocolFeeSetTest is Test {
    function complement(uint256 x) internal pure returns (uint256 result) {
        // Equivalent to:
        // result = (x < ONE) ? (ONE - x) : 0;
        assembly ("memory-safe") {
            result := mul(lt(x, ONE), sub(ONE, x))
        }
    }

    uint256 internal constant ONE = 1e18; // 18 decimal places
    uint256 internal constant TWO = 2 * ONE;
    uint256 internal constant FOUR = 4 * ONE;
    uint256 internal constant MAX_POW_RELATIVE_ERROR = 10000; // 10^(-14)
    uint256 internal constant FEE_SCALING_FACTOR = 1e11;
    uint256 internal constant MAX_PROTOCOL_FEE = 50e16;

    function mulDown(uint256 a, uint256 b) internal pure returns (uint256) {
        // Multiplication overflow protection is provided by Solidity 0.8.x
        uint256 product = a * b;

        return product / ONE;
    }

    function computeAggregatePercentage(uint poolCreatorFeePercentage, uint protocolFeePercentage) public view returns (uint aggregateFeePercentage) {
        aggregateFeePercentage =
            protocolFeePercentage +
            mulDown(complement(protocolFeePercentage), poolCreatorFeePercentage);
    }

    error FeePrecisionTooHigh();
    function _ensureValidPrecision(uint256 feePercentage) private pure {
        // Primary fee percentages are 18-decimal values, stored here in 64 bits, and calculated with full 256-bit
        // precision. However, the resulting aggregate fees are stored in the Vault with 24-bit precision, which
        // corresponds to 0.00001% resolution (i.e., a fee can be 1%, 1.00001%, 1.00002%, but not 1.000005%).
        // Ensure there will be no precision loss in the Vault - which would lead to a discrepancy between the
        // aggregate fee calculated here and that stored in the Vault.
        if ((feePercentage / FEE_SCALING_FACTOR) * FEE_SCALING_FACTOR != feePercentage) {
            revert FeePrecisionTooHigh();
        }
    }

    function test_RoundingBalancer(uint256 protocolFee) public {
        uint256 _protocolFee = bound(protocolFee, 1, (MAX_PROTOCOL_FEE/FEE_SCALING_FACTOR));
        _protocolFee = FEE_SCALING_FACTOR*_protocolFee;
        uint _poolCreatorFee = 20e16 + FEE_SCALING_FACTOR;

        uint256 aggregateFee = computeAggregatePercentage(_poolCreatorFee, _protocolFee);

        vm.expectRevert();
        _ensureValidPrecision(aggregateFee);
    }
}