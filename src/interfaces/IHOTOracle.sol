// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import { AggregatorV3Interface } from '../vendor/chainlink/AggregatorV3Interface.sol';

interface IHOTOracle {
    /**
	    @notice Price feeds for token{0,1}, denominated in USD.
	    @dev These must be valid Chainlink Price Feeds.
     */
    function feedToken0() external view returns (AggregatorV3Interface);
    function feedToken1() external view returns (AggregatorV3Interface);

    /**
	    @notice Maximum allowed duration for each oracle update, in seconds.
        @dev Oracle prices are considered stale beyond this threshold,
             meaning that all swaps should revert.
     */
    function maxOracleUpdateDurationFeed0() external view returns (uint32);
    function maxOracleUpdateDurationFeed1() external view returns (uint32);

    /**
        @notice Calculates sqrt oracle price, in Q96 format, by querying both price feeds. 
     */
    function getSqrtOraclePriceX96() external view returns (uint160 sqrtOraclePriceX96);
}
