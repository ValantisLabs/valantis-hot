// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { HOTOracle } from '../../src/HOTOracle.sol';
import { AggregatorV3Interface } from '../../src/vendor/chainlink/AggregatorV3Interface.sol';

contract HOTOracleHelper is HOTOracle {
    constructor(
        address _token0,
        address _token1,
        address _feedToken0,
        address _feedToken1,
        uint32 _maxOracleUpdateDurationFeed0,
        uint32 _maxOracleUpdateDurationFeed1
    )
        HOTOracle(
            _token0,
            _token1,
            _feedToken0,
            _feedToken1,
            _maxOracleUpdateDurationFeed0,
            _maxOracleUpdateDurationFeed1
        )
    {}

    function setFeeds(address _feedToken0, address _feedToken1) public {
        return _setFeeds(_feedToken0, _feedToken1);
    }

    function getOraclePriceUSD(
        AggregatorV3Interface feed,
        uint32 maxOracleUpdateDuration
    ) public view returns (uint256) {
        return _getOraclePriceUSD(feed, maxOracleUpdateDuration);
    }

    function calculateSqrtOraclePriceX96(
        uint256 oraclePrice0USD,
        uint256 oraclePrice1USD,
        uint256 oracle0Base,
        uint256 oracle1Base
    ) public view returns (uint160) {
        return _calculateSqrtOraclePriceX96(oraclePrice0USD, oraclePrice1USD, oracle0Base, oracle1Base);
    }
}
