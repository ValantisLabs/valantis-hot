// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { console } from 'forge-std/console.sol';

import { Base } from 'valantis-core/test/base/Base.sol';

import { MockChainlinkOracle } from 'test/mocks/MockChainlinkOracle.sol';

import {
    SovereignPool,
    SovereignPoolBase,
    SovereignPoolConstructorArgs
} from 'valantis-core/test/base/SovereignPoolBase.t.sol';
import { SOT } from 'src/SOT.sol';
import { SOTConstructorArgs } from 'src/structs/SOTStructs.sol';

import { SOTDeployer } from 'test/deployers/SOTDeployer.sol';

contract SOTBase is SovereignPoolBase, SOTDeployer {
    SOT public sot;

    MockChainlinkOracle public feedToken0;
    MockChainlinkOracle public feedToken1;

    function setUp() public override {
        _setupBase();

        (feedToken0, feedToken1) = deployChainlinkOracles(18, 18);
        // Set initial price to 2000 for token0 and 1 for token1 (Similar to Eth/USDC pair)
        feedToken0.appendAnswer(2000e18);
        feedToken0.appendAnswer(1e18);

        SovereignPoolConstructorArgs memory poolArgs = _generateDefaultConstructorArgs();
        pool = this.deploySovereignPool(poolArgs);
        sot = deployAndSetDefaultSOT(pool);
    }

    function deployAndSetDefaultSOT(SovereignPool _pool) public returns (SOT _sot) {
        SOTConstructorArgs memory args = SOTConstructorArgs({
            pool: address(_pool),
            liquidityProvider: address(this),
            feedToken0: address(feedToken0),
            feedToken1: address(feedToken1),
            maxDelay: 9 minutes,
            maxOracleUpdateDuration: 10 minutes,
            solverMaxDiscountBips: 200, // 2%
            oraclePriceMaxDiffBips: 50, // 0.5%
            minAmmFeeGrowth: 1,
            maxAmmFeeGrowth: 100,
            minAmmFee: 1 // 0.01%
        });

        vm.startPrank(_pool.poolManager());
        _sot = this.deploySOT(_pool, args);
        _pool.setALM(address(_sot));
        _pool.setSwapFeeModule(address(_sot));
        vm.stopPrank();
    }

    function deployChainlinkOracles(
        uint8 feedToken0Decimals,
        uint8 feedToken1Decimals
    ) public returns (MockChainlinkOracle _feedToken0, MockChainlinkOracle _feedToken1) {
        _feedToken0 = new MockChainlinkOracle(feedToken0Decimals);
        _feedToken1 = new MockChainlinkOracle(feedToken1Decimals);
        return (_feedToken0, _feedToken1);
    }
}
