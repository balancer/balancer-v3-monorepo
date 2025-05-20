// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IVault } from "@balancer-labs/v3-interfaces/contracts/vault/IVault.sol";
import { Rounding } from "@balancer-labs/v3-interfaces/contracts/vault/VaultTypes.sol";
import { IWeightedPool } from "@balancer-labs/v3-interfaces/contracts/pool-weighted/IWeightedPool.sol";
import {
    IChainlinkAggregatorV3
} from "@balancer-labs/v3-interfaces/contracts/standalone-utils/IChainlinkAggregatorV3.sol";

import { FixedPoint } from "@balancer-labs/v3-solidity-utils/contracts/math/FixedPoint.sol";
import { InputHelpers } from "@balancer-labs/v3-solidity-utils/contracts/helpers/InputHelpers.sol";

contract WeightedLPOracle is IChainlinkAggregatorV3 {
    using FixedPoint for uint256;
    using SafeCast for *;

    error UnsupportedDecimals();

    uint256 internal constant _WAD_DECIMALS = 18;

    uint256 internal immutable _version;
    IVault internal immutable _vault;
    IWeightedPool public immutable pool;

    uint256 internal immutable _totalTokens;

    string internal _description;

    uint256 internal immutable _weight0;
    uint256 internal immutable _weight1;
    uint256 internal immutable _weight2;
    uint256 internal immutable _weight3;
    uint256 internal immutable _weight4;
    uint256 internal immutable _weight5;
    uint256 internal immutable _weight6;
    uint256 internal immutable _weight7;

    IChainlinkAggregatorV3 internal immutable _feedToken0;
    IChainlinkAggregatorV3 internal immutable _feedToken1;
    IChainlinkAggregatorV3 internal immutable _feedToken2;
    IChainlinkAggregatorV3 internal immutable _feedToken3;
    IChainlinkAggregatorV3 internal immutable _feedToken4;
    IChainlinkAggregatorV3 internal immutable _feedToken5;
    IChainlinkAggregatorV3 internal immutable _feedToken6;
    IChainlinkAggregatorV3 internal immutable _feedToken7;

    uint256 internal immutable _feedToken0DecimalScalingFactor;
    uint256 internal immutable _feedToken1DecimalScalingFactor;
    uint256 internal immutable _feedToken2DecimalScalingFactor;
    uint256 internal immutable _feedToken3DecimalScalingFactor;
    uint256 internal immutable _feedToken4DecimalScalingFactor;
    uint256 internal immutable _feedToken5DecimalScalingFactor;
    uint256 internal immutable _feedToken6DecimalScalingFactor;
    uint256 internal immutable _feedToken7DecimalScalingFactor;

    constructor(IVault vault_, IWeightedPool pool_, IChainlinkAggregatorV3[] memory feeds_, uint256 version_) {
        _version = version_;
        _vault = vault_;
        pool = pool_;

        IERC20[] memory tokens = vault_.getPoolTokens(address(pool_));
        uint256[] memory weights = pool_.getNormalizedWeights();
        uint totalTokens = tokens.length;

        _totalTokens = totalTokens;
        _description = string.concat(IERC20Metadata(address(pool)).symbol(), "/USD");

        InputHelpers.ensureInputLengthMatch(totalTokens, feeds_.length);

        for (uint256 i = 0; i < totalTokens; i++) {
            if (i == 0) {
                _feedToken0 = feeds_[i];
                _weight0 = weights[i];
                _feedToken0DecimalScalingFactor = _calculateFeedTokenDecimalScalingFactor(feeds_[i]);
            } else if (i == 1) {
                _feedToken1 = feeds_[i];
                _weight1 = weights[i];
                _feedToken1DecimalScalingFactor = _calculateFeedTokenDecimalScalingFactor(feeds_[i]);
            } else if (i == 2) {
                _feedToken2 = feeds_[i];
                _weight2 = weights[i];
                _feedToken2DecimalScalingFactor = _calculateFeedTokenDecimalScalingFactor(feeds_[i]);
            } else if (i == 3) {
                _feedToken3 = feeds_[i];
                _weight3 = weights[i];
                _feedToken3DecimalScalingFactor = _calculateFeedTokenDecimalScalingFactor(feeds_[i]);
            } else if (i == 4) {
                _feedToken4 = feeds_[i];
                _weight4 = weights[i];
                _feedToken4DecimalScalingFactor = _calculateFeedTokenDecimalScalingFactor(feeds_[i]);
            } else if (i == 5) {
                _feedToken5 = feeds_[i];
                _weight5 = weights[i];
                _feedToken5DecimalScalingFactor = _calculateFeedTokenDecimalScalingFactor(feeds_[i]);
            } else if (i == 6) {
                _feedToken6 = feeds_[i];
                _weight6 = weights[i];
                _feedToken6DecimalScalingFactor = _calculateFeedTokenDecimalScalingFactor(feeds_[i]);
            } else if (i == 7) {
                _feedToken7 = feeds_[i];
                _weight7 = weights[i];
                _feedToken7DecimalScalingFactor = _calculateFeedTokenDecimalScalingFactor(feeds_[i]);
            }
        }
    }

    function version() external view returns (uint256) {
        return _version;
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function description() external view returns (string memory) {
        return _description;
    }

    function getRoundData(
        uint80
    )
        external
        pure
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (0, 0, 0, 0, 0);
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        (int256[] memory prices, uint256 _updatedAt) = _getFeedData();

        uint256 tvl = _calculateTVL(prices);
        uint256 totalSupply = IERC20(address(pool)).totalSupply();

        uint256 lpPrice = tvl.divDown(totalSupply);

        return (0, lpPrice.toInt256(), 0, _updatedAt, 0);
    }

    function _calculateTVL(int256[] memory prices) internal view returns (uint256 tvl) {
        uint256 totalTokens = _totalTokens;

        uint256[] memory weights = _getWeights(totalTokens);
        (, , , uint256[] memory lastBalancesLiveScaled18) = _vault.getPoolTokenInfo(address(pool));

        uint256 k = pool.computeInvariant(lastBalancesLiveScaled18, Rounding.ROUND_UP);

        tvl = FixedPoint.ONE;
        for (uint256 i = 0; i < totalTokens; i++) {
            tvl = tvl.mulUp(prices[i].toUint256().divDown(weights[i]).powUp(weights[i]));
        }

        tvl = tvl.mulUp(k);
    }

    function _getFeedData() internal view returns (int256[] memory prices, uint256 updatedAt) {
        uint256 totalTokens = _totalTokens;
        IChainlinkAggregatorV3[] memory feeds = _getFeeds(totalTokens);
        uint256[] memory feedDecimalScalingFactors = _getFeedTokenDecimalScalingFactors(totalTokens);

        prices = new int256[](totalTokens);

        updatedAt = type(uint256).max;
        for (uint256 i = 0; i < totalTokens; i++) {
            (, int256 answer, , uint256 feedUpdatedAt, ) = feeds[i].latestRoundData();
            prices[i] = answer * feedDecimalScalingFactors[i].toInt256();

            updatedAt = updatedAt < feedUpdatedAt ? updatedAt : feedUpdatedAt;
        }
    }

    function _getFeeds(uint256 totalTokens) internal view virtual returns (IChainlinkAggregatorV3[] memory) {
        IChainlinkAggregatorV3[] memory feeds = new IChainlinkAggregatorV3[](totalTokens);

        // prettier-ignore
        {
            feeds[0] = _feedToken0;
            feeds[1] = _feedToken1;
            if (totalTokens > 2) { feeds[2] = _feedToken2; } else { return feeds; }
            if (totalTokens > 3) { feeds[3] = _feedToken3; } else { return feeds; }
            if (totalTokens > 4) { feeds[4] = _feedToken4; } else { return feeds; }
            if (totalTokens > 5) { feeds[5] = _feedToken5; } else { return feeds; }
            if (totalTokens > 6) { feeds[6] = _feedToken6; } else { return feeds; }
            if (totalTokens > 7) { feeds[7] = _feedToken7; }
        }

        return feeds;
    }

    function _getFeedTokenDecimalScalingFactors(uint256 totalTokens) internal view returns (uint256[] memory) {
        uint256[] memory feedTokenDecimalScalingFactors = new uint256[](totalTokens);

        // prettier-ignore
        {
            feedTokenDecimalScalingFactors[0] = _feedToken0DecimalScalingFactor;
            feedTokenDecimalScalingFactors[1] = _feedToken1DecimalScalingFactor;
            if (totalTokens > 2) { feedTokenDecimalScalingFactors[2] = _feedToken2DecimalScalingFactor; } 
                else { return feedTokenDecimalScalingFactors; }
            if (totalTokens > 3) { feedTokenDecimalScalingFactors[3] = _feedToken3DecimalScalingFactor; }
                else { return feedTokenDecimalScalingFactors; }
            if (totalTokens > 4) { feedTokenDecimalScalingFactors[4] = _feedToken4DecimalScalingFactor; }
                else { return feedTokenDecimalScalingFactors; }
            if (totalTokens > 5) { feedTokenDecimalScalingFactors[5] = _feedToken5DecimalScalingFactor; } 
                else { return feedTokenDecimalScalingFactors; }
            if (totalTokens > 6) { feedTokenDecimalScalingFactors[6] = _feedToken6DecimalScalingFactor; } 
                else { return feedTokenDecimalScalingFactors; }
            if (totalTokens > 7) { feedTokenDecimalScalingFactors[7] = _feedToken7DecimalScalingFactor; }
        }

        return feedTokenDecimalScalingFactors;
    }

    function _getWeights(uint256 totalTokens) internal view returns (uint256[] memory) {
        uint256[] memory weights = new uint256[](totalTokens);

        // prettier-ignore
        {
            weights[0] = _weight0;
            weights[1] = _weight1;
            if (totalTokens > 2) { weights[2] = _weight2; } else { return weights; }
            if (totalTokens > 3) { weights[3] = _weight3; } else { return weights; }
            if (totalTokens > 4) { weights[4] = _weight4; } else { return weights; }
            if (totalTokens > 5) { weights[5] = _weight5; } else { return weights; }
            if (totalTokens > 6) { weights[6] = _weight6; } else { return weights; }
            if (totalTokens > 7) { weights[7] = _weight7; }
        }

        return weights;
    }

    function _calculateFeedTokenDecimalScalingFactor(IChainlinkAggregatorV3 feed) internal view returns (uint256) {
        uint256 feedDecimals = feed.decimals();

        if (feedDecimals > _WAD_DECIMALS) {
            revert UnsupportedDecimals();
        }

        return 10 ** (_WAD_DECIMALS - feedDecimals);
    }
}
