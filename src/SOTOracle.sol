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

    error SOTOracle___getSqrtOraclePriceX96_sqrtOraclePriceOutOfBounds();
    error SOTOracle___getOraclePriceUSD_stalePrice();

    /**
	    @notice Base unit for token{0,1}.
          For example: token0Base = 10 ** token0Decimals;
        @dev `token0` and `token1` must be the same as this module's Sovereign Pool.
     */
    uint256 public immutable token0Base;
    uint256 public immutable token1Base;

    /**
	    @notice Base unit for feedToken{0,1}.
          For example: feedToken0Base = 10 ** feedToken0Decimals;
        @dev `token0` and `token1` must be the same as this module's Sovereign Pool.
     */
    uint256 public immutable feedToken0Base;
    uint256 public immutable feedToken1Base;

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
        token0Base = 10 ** IERC20Metadata(_token0).decimals();
        token1Base = 10 ** IERC20Metadata(_token1).decimals();

        maxOracleUpdateDuration = _maxOracleUpdateDuration;

        feedToken0 = AggregatorV3Interface(_feedToken0);
        feedToken1 = AggregatorV3Interface(_feedToken1);

        feedToken0Base = 10 ** feedToken0.decimals();
        feedToken1Base = 10 ** feedToken1.decimals();
    }

    function getSqrtOraclePriceX96() public view returns (uint160 sqrtOraclePriceX96) {
        uint256 oraclePrice0USD = _getOraclePriceUSD(feedToken0);
        uint256 oraclePrice1USD = _getOraclePriceUSD(feedToken1);

        sqrtOraclePriceX96 = _calculateSqrtOraclePriceX96(
            oraclePrice0USD,
            oraclePrice1USD,
            feedToken0Base,
            feedToken1Base,
            token0Base,
            token1Base
        );

        if (sqrtOraclePriceX96 < SOTConstants.MIN_SQRT_PRICE || sqrtOraclePriceX96 > SOTConstants.MAX_SQRT_PRICE) {
            revert SOTOracle___getSqrtOraclePriceX96_sqrtOraclePriceOutOfBounds();
        }
    }

    function _getOraclePriceUSD(AggregatorV3Interface feed) internal view returns (uint256 oraclePriceUSD) {
        (, int256 oraclePriceUSDInt, , uint256 updatedAt, ) = feed.latestRoundData();

        if (block.timestamp - updatedAt > maxOracleUpdateDuration) {
            revert SOTOracle___getOraclePriceUSD_stalePrice();
        }

        // TODO: Add checks for L2 sequencer uptime

        // TODO: Maybe unsafe uint256 conversion can be used
        oraclePriceUSD = oraclePriceUSDInt.toUint256();
    }

    function _calculateSqrtOraclePriceX96(
        uint256 oraclePrice0USD,
        uint256 oraclePrice1USD,
        uint256 oracle0Base,
        uint256 oracle1Base,
        uint256 _token0Base,
        uint256 _token1Base
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
                ((oraclePrice0USD * oracle1Base * _token1Base) << 96) / (oraclePrice1USD * oracle0Base * _token0Base)
            ) << 48).toUint160();
    }
}
