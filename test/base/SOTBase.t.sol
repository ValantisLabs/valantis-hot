// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { console } from 'forge-std/console.sol';

import {
    SovereignPool,
    SovereignPoolBase,
    SovereignPoolConstructorArgs
} from 'valantis-core/test/base/SovereignPoolBase.t.sol';
import { Base } from 'valantis-core/test/base/Base.sol';

import { MockChainlinkOracle } from 'test/mocks/MockChainlinkOracle.sol';

import { SOT } from 'src/SOT.sol';
import { SOTConstructorArgs, SolverOrderType } from 'src/structs/SOTStructs.sol';
import { SOTOracle } from 'src/SOTOracle.sol';

import { SOTDeployer } from 'test/deployers/SOTDeployer.sol';
import { SafeCast } from 'valantis-core/lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol';

contract SOTBase is SovereignPoolBase, SOTDeployer {
    using SafeCast for uint256;

    SOT public sot;

    MockChainlinkOracle public feedToken0;
    MockChainlinkOracle public feedToken1;

    function setUp() public virtual override {
        _setupBase();

        (feedToken0, feedToken1) = deployChainlinkOracles(18, 18);
        // Set initial price to 2000 for token0 and 1 for token1 (Similar to Eth/USDC pair)
        feedToken0.updateAnswer(2000e18);
        feedToken0.updateAnswer(1e18);

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

    /// @dev This is only used for testing, during deployment SOTOracle is inherited by SOT
    function deploySOTOracleIndependently(
        MockChainlinkOracle _feedToken0,
        MockChainlinkOracle _feedToken1,
        uint32 _maxOracleUpdateDuration
    ) public returns (SOTOracle oracle) {
        oracle = new SOTOracle(
            address(pool.token0()),
            address(pool.token1()),
            address(_feedToken0),
            address(_feedToken1),
            _maxOracleUpdateDuration
        );
    }

    function _getSensibleSOTParams() internal returns (SolverOrderType memory sotParams) {
        // Sensible Defaults
        sotParams = SolverOrderType({
            amountInMax: 100e18,
            solverPriceX192Discounted: 1980 << 192, // 1% discount to first solver
            solverPriceX192Base: 2000 << 192,
            sqrtSpotPriceX96New: 45 << 96, // AMM spot price 2025
            authorizedSender: msg.sender,
            authorizedRecipient: makeAddr('RECIPIENT'),
            signatureTimestamp: (block.timestamp).toUint32(),
            expiry: 24, // 2 Blocks
            feeMin: 10,
            feeMax: 100,
            feeGrowth: 5,
            nonce: 1,
            expectedFlag: 1
        });
    }
}
