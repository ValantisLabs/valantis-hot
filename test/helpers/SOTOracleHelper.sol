// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { SOTOracle } from 'src/SOTOracle.sol';
import { AggregatorV3Interface } from 'src/vendor/chainlink/AggregatorV3Interface.sol';

contract SOTOracleHelper is SOTOracle {
    constructor(
        address _token0,
        address _token1,
        address _feedToken0,
        address _feedToken1,
        uint32 _maxOracleUpdateDuration
    ) SOTOracle(_token0, _token1, _feedToken0, _feedToken1, _maxOracleUpdateDuration) {}

    function getOraclePriceUSD(AggregatorV3Interface feed) public returns (uint256) {
        return _getOraclePriceUSD(feed);
    }

    function calculateSqrtOraclePriceX96(
        uint256 oraclePrice0USD,
        uint256 oraclePrice1USD,
        uint256 oracle0Base,
        uint256 oracle1Base,
        uint256 _token0Base,
        uint256 _token1Base
    ) public view returns (uint160) {
        return
            _calculateSqrtOraclePriceX96(
                oraclePrice0USD,
                oraclePrice1USD,
                oracle0Base,
                oracle1Base,
                _token0Base,
                _token1Base
            );
    }
}
