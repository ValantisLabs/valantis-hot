// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {
    IERC20Metadata
} from 'valantis-core/lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import { Math } from 'valantis-core/lib/openzeppelin-contracts/contracts/utils/math/Math.sol';
import { SafeCast } from 'valantis-core/lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol';

import { AggregatorV3Interface } from 'src/vendor/chainlink/AggregatorV3Interface.sol';
import { SOTParams } from 'src/libraries/SOTParams.sol';
import { SOTConstants } from 'src/libraries/SOTConstants.sol';

contract SOTOracle {
    using SafeCast for int256;
    using SafeCast for uint256;

    /************************************************
     *  CUSTOM ERRORS
     ***********************************************/

    error SOTOracle__constructor_invalidFeedToken0();
    error SOTOracle__constructor_invalidFeedToken1();
    error SOTOracle___getOraclePriceUSD_stalePrice();
    error SOTOracle___getSqrtOraclePriceX96_sqrtOraclePriceOutOfBounds();

    /************************************************
     *  IMMUTABLES
     ***********************************************/

    /**
	    @notice Base unit for token{0,1}.
          For example: _token0Base = 10 ** token0Decimals;
        @dev `token0` and `token1` must be the same as this module's Sovereign Pool.
     */
    uint256 private immutable _token0Base;
    uint256 private immutable _token1Base;

    /**
	    @notice Maximum allowed duration for each oracle update, in seconds.
        @dev Oracle prices are considered stale beyond this threshold,
             meaning that all swaps should revert.
     */
    uint32 public immutable maxOracleUpdateDurationFeed0;
    uint32 public immutable maxOracleUpdateDurationFeed1;

    /**
	    @notice Price feeds for token{0,1}, denominated in USD.
	    @dev These must be valid Chainlink Price Feeds.
     */
    AggregatorV3Interface public immutable feedToken0;
    AggregatorV3Interface public immutable feedToken1;

    /************************************************
     *  CONSTRUCTOR
     ***********************************************/

    constructor(
        address _token0,
        address _token1,
        address _feedToken0,
        address _feedToken1,
        uint32 _maxOracleUpdateDurationFeed0,
        uint32 _maxOracleUpdateDurationFeed1
    ) {
        _token0Base = 10 ** IERC20Metadata(_token0).decimals();
        _token1Base = 10 ** IERC20Metadata(_token1).decimals();

        // TODO: Enforce sensible bound
        maxOracleUpdateDurationFeed0 = _maxOracleUpdateDurationFeed0;
        maxOracleUpdateDurationFeed1 = _maxOracleUpdateDurationFeed1;

        if (_feedToken0 == address(0)) {
            revert SOTOracle__constructor_invalidFeedToken0();
        }

        if (_feedToken1 == address(0)) {
            revert SOTOracle__constructor_invalidFeedToken1();
        }

        feedToken0 = AggregatorV3Interface(_feedToken0);
        feedToken1 = AggregatorV3Interface(_feedToken1);
    }

    /************************************************
     *  PUBLIC FUNCTIONS
     ***********************************************/

    function getSqrtOraclePriceX96() public view returns (uint160 sqrtOraclePriceX96) {
        uint256 oraclePrice0USD = _getOraclePriceUSD(feedToken0, maxOracleUpdateDurationFeed0);
        uint256 oraclePrice1USD = _getOraclePriceUSD(feedToken1, maxOracleUpdateDurationFeed1);

        sqrtOraclePriceX96 = _calculateSqrtOraclePriceX96(
            oraclePrice0USD,
            oraclePrice1USD,
            10 ** feedToken0.decimals(),
            10 ** feedToken1.decimals()
        );

        if (sqrtOraclePriceX96 < SOTConstants.MIN_SQRT_PRICE || sqrtOraclePriceX96 > SOTConstants.MAX_SQRT_PRICE) {
            revert SOTOracle___getSqrtOraclePriceX96_sqrtOraclePriceOutOfBounds();
        }
    }

    /************************************************
     *  INTERNAL FUNCTIONS
     ***********************************************/

    function _getOraclePriceUSD(
        AggregatorV3Interface feed,
        uint32 maxOracleUpdateDuration
    ) internal view returns (uint256 oraclePriceUSD) {
        (, int256 oraclePriceUSDInt, , uint256 updatedAt, ) = feed.latestRoundData();

        if (block.timestamp - updatedAt > maxOracleUpdateDuration) {
            revert SOTOracle___getOraclePriceUSD_stalePrice();
        }

        // TODO: Add checks for L2 sequencer uptime

        oraclePriceUSD = oraclePriceUSDInt.toUint256();
    }

    function _calculateSqrtOraclePriceX96(
        uint256 oraclePrice0USD,
        uint256 oraclePrice1USD,
        uint256 oracle0Base,
        uint256 oracle1Base
    ) internal view returns (uint160) {
        // Source: https://github.com/timeless-fi/bunni-oracle/blob/main/src/BunniOracle.sol

        // We are given two price feeds: token0 / USD and token1 / USD.
        // In order to compare token0 and token1 amounts, we need to convert
        // them both into USD:
        //
        // amount1USD = _token1Base / (oraclePrice1USD / oracle1Base)
        // amount0USD = _token0Base / (oraclePrice0USD / oracle0Base)
        //
        // Following SOT and sqrt spot price definition:
        //
        // sqrtOraclePriceX96 = sqrt(amount1USD / amount0USD) * 2 ** 96
        // solhint-disable-next-line max-line-length
        // = sqrt(oraclePrice0USD * _token1Base * oracle1Base) * 2 ** 96 / (oraclePrice1USD * _token0Base * oracle0Base)) * 2 ** 48

        uint256 oraclePriceX96 = Math.mulDiv(
            oraclePrice0USD * oracle1Base * _token1Base,
            1 << 96,
            oraclePrice1USD * oracle0Base * _token0Base
        );
        return (Math.sqrt(oraclePriceX96) << 48).toUint160();
    }
}
