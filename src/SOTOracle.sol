// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {
    IERC20Metadata
} from 'valantis-core/lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import { Math } from 'valantis-core/lib/openzeppelin-contracts/contracts/utils/math/Math.sol';
import { SafeCast } from 'valantis-core/lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol';
import { AggregatorV3Interface } from 'src/vendor/chainlink/AggregatorV3Interface.sol';

abstract contract SOTOracle {
    using SafeCast for int256;
    using SafeCast for uint256;

    error SOTOracle___getOraclePriceUSD_stalePrice();

    /**
	    @notice Decimals for token{0,1}.
        @dev `token0` and `token1` must be the same as this module's Sovereign Pool.
     */
    uint8 public immutable token0Decimals;
    uint8 public immutable token1Decimals;

    /**
	    @notice Base unit for token{0,1}.
          For example: token0Base = 10 ** token0Decimals;
        @dev `token0` and `token1` must be the same as this module's Sovereign Pool.
     */
    uint256 public immutable token0Base;
    uint256 public immutable token1Base;

    /**
	    @notice Maximum allowed duration for each oracle update, in seconds.
        @dev Oracle prices are considered stale beyond this threshold,
             meaning that all swaps should revert.
     */
    uint32 public immutable maxOracleUpdateDuration;

    /**
	    @notice Price feeds for token{0,1}, denominated in USD.
	    @dev These must be valid Chainlink Price Feeds.
     */
    AggregatorV3Interface public immutable feedToken0;
    AggregatorV3Interface public immutable feedToken1;

    constructor(
        address _token0,
        address _token1,
        address _feedToken0,
        address _feedToken1,
        uint32 _maxOracleUpdateDuration
    ) {
        token0Decimals = IERC20Metadata(_token0).decimals();
        token1Decimals = IERC20Metadata(_token1).decimals();

        token0Base = 10 ** token0Decimals;
        token1Base = 10 ** token1Decimals;

        maxOracleUpdateDuration = _maxOracleUpdateDuration;

        feedToken0 = AggregatorV3Interface(_feedToken0);
        feedToken1 = AggregatorV3Interface(_feedToken1);
    }

    function _getSqrtOraclePriceX96() internal view returns (uint160) {
        (uint256 oraclePrice0USD, uint256 oracle0Base) = _getOraclePriceUSD(feedToken0);
        (uint256 oraclePrice1USD, uint256 oracle1Base) = _getOraclePriceUSD(feedToken1);

        return _calculateSqrtOraclePriceX96(oraclePrice0USD, oraclePrice1USD, oracle0Base, oracle1Base);
    }

    function _getOraclePriceUSD(
        AggregatorV3Interface feed
    ) private view returns (uint256 oraclePriceUSD, uint256 oracleBase) {
        (, int256 oraclePriceUSDInt, , uint256 updatedAt, ) = feed.latestRoundData();

        if (block.timestamp - updatedAt > maxOracleUpdateDuration) {
            revert SOTOracle___getOraclePriceUSD_stalePrice();
        }

        // TODO: Add checks for L2 sequencer uptime

        // TODO: Maybe unsafe uint256 conversion can be used
        oraclePriceUSD = oraclePriceUSDInt.toUint256();
        // TODO: Maybe those can be cached as immutables
        oracleBase = 10 ** (feed.decimals());
    }

    function _calculateSqrtOraclePriceX96(
        uint256 oraclePrice0USD,
        uint256 oraclePrice1USD,
        uint256 oracle0Base,
        uint256 oracle1Base
    ) internal view returns (uint160) {
        // We are given two price feeds: token0 / USD and token1 / USD.
        // In order to compare token0 and token1 amounts, we need to convert
        // them both into USD:
        //
        // amount1USD = token1Base / (oraclePrice1USD / oracle1Base)
        // amount0USD = token0Base / (oraclePrice0USD / oracle0Base)
        //
        // Following SOT and sqrt spot price definition:
        //
        // oraclePriceX128 = sqrt(amount1USD / amount0USD) * 2 ** 96
        // solhint-disable-next-line max-line-length
        // = sqrt(oraclePrice0USD * token1Base * oracle1Base) * 2 ** 96 / (oraclePrice1USD * token0Base * oracle0Base)) * 2 ** 48

        return
            (Math.sqrt(
                ((oraclePrice0USD * oracle1Base * token1Base) << 96) / (oraclePrice1USD * oracle0Base * token0Base)
            ) << 48).toUint160();
    }
}
