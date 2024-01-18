// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import 'forge-std/Console.sol';

import { SOTBase } from 'test/base/SOTBase.t.sol';
import { SOTOracle } from 'src/SOTOracle.sol';

contract SOTOracleConcrete is SOTBase {
    SOTOracle public oracle;

    function setUp() public override {
        super.setUp();

        (feedToken0, feedToken1) = deployChainlinkOracles(8, 8);
        oracle = deploySOTOracleIndependently(feedToken0, feedToken1, 10 minutes);
    }

    function test_constructor() public {
        assertEq(address(oracle.feedToken0()), address(feedToken0));
        assertEq(address(oracle.feedToken1()), address(feedToken1));
        assertEq(oracle.maxOracleUpdateDuration(), 10 minutes);
        assertEq(oracle.feedToken0Base(), 10 ** feedToken0.decimals());
        assertEq(oracle.feedToken1Base(), 10 ** feedToken1.decimals());
    }

    // function test__getOraclePriceUSD() public {
    //     feedToken0.updateAnswer(2000e18);
    //     feedToken1.updateAnswer(50e6);

    //     uint256 price0 = oracle._getOraclePriceUSD(address(pool.token0()), address(pool.token1()));
    //     uint256 price1 = oracle._getOraclePriceUSD(address(pool.token1()), address(pool.token0()));

    //     assertEq(price0, 2000e18);
    //     assertEq(price1, 50e6);
    // }

    function test_getSqrtOraclePriceX96() public {
        // Decimals of token0 = 18
        // Decimals of token1 = 18
        // Decimals of feed0 = 8
        // Decimals of feed1 = 8

        feedToken0.updateAnswer(2000e8); // Assume price of Eth/ USD
        feedToken1.updateAnswer(1e8); // Assume price of USDC/USD

        // Wolfram Alpha Result
        // sqrt( 2000 * 2**192 ) = 3543191142285914205922034323214.52013064235901452874517487228
        // sqrt ( 2000 ) * 2**96 = 3543191142285914205922034323214.52013064235901452874517487228
        assertApproxEqAbs(oracle.getSqrtOraclePriceX96(), 3543191142285914205922034323214, 1);
    }
}
