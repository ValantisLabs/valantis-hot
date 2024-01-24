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
import { SOTOracleHelper } from 'test/helpers/SOTOracleHelper.sol';

import { SOTDeployer } from 'test/deployers/SOTDeployer.sol';
import { SafeCast } from 'valantis-core/lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol';

import { Math } from 'valantis-core/lib/openzeppelin-contracts/contracts/utils/math/Math.sol';

contract SOTBase is SovereignPoolBase, SOTDeployer {
    using SafeCast for uint256;

    SOT public sot;

    MockChainlinkOracle public feedToken0;
    MockChainlinkOracle public feedToken1;

    function setUp() public virtual override {
        _setupBase();

        (feedToken0, feedToken1) = deployChainlinkOracles(8, 8);
        // Set initial price to 2000 for token0 and 1 for token1 (Similar to Eth/USDC pair)
        feedToken0.updateAnswer(2000e18);
        feedToken0.updateAnswer(1e18);

        SovereignPoolConstructorArgs memory poolArgs = _generateDefaultConstructorArgs();
        pool = this.deploySovereignPool(poolArgs);
        sot = deployAndSetDefaultSOT(pool);

        _addToContractsToApprove(address(pool));
        _addToContractsToApprove(address(sot));
    }

    function deployAndSetDefaultSOT(SovereignPool _pool) public returns (SOT _sot) {
        SOTConstructorArgs memory args = SOTConstructorArgs({
            pool: address(_pool),
            liquidityProvider: address(this),
            feedToken0: address(feedToken0),
            feedToken1: address(feedToken1),
            sqrtSpotPriceX96: getSqrtPriceX96(2000 ** feedToken0.decimals(), 1 ** feedToken1.decimals()),
            sqrtPriceLowX96: getSqrtPriceX96(1500 ** feedToken0.decimals(), 1 ** feedToken1.decimals()),
            sqrtPriceHighX96: getSqrtPriceX96(2500 ** feedToken0.decimals(), 1 ** feedToken1.decimals()),
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

    /// @dev This is only used for testing, during deployment SOTOracle is inherited by SOT
    function deploySOTOracleHelper(
        MockChainlinkOracle _feedToken0,
        MockChainlinkOracle _feedToken1,
        uint32 _maxOracleUpdateDuration
    ) public returns (SOTOracleHelper oracle) {
        oracle = new SOTOracleHelper(
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
            authorizedSender: address(this),
            authorizedRecipient: makeAddr('RECIPIENT'),
            signatureTimestamp: (block.timestamp).toUint32(),
            expiry: 24, // 2 Blocks
            feeMin: 10, // 0.1%
            feeMax: 100, // 1%
            feeGrowth: 5, // 5 Bips per second
            nonce: 1,
            expectedFlag: 1
        });
    }

    function _calculateSqrtOraclePriceX96(
        uint256 oraclePrice0USD,
        uint256 oraclePrice1USD,
        uint256 oracle0Base,
        uint256 oracle1Base,
        uint256 _token0Base,
        uint256 _token1Base
    ) internal pure returns (uint160) {
        // We are given two price feeds: token0 / USD and token1 / USD.
        // In order to compare token0 and token1 amounts, we need to convert
        // them both into USD:
        //
        // amount1USD = token1Base / (oraclePrice1USD / oracle1Base)
        // amount0USD = token0Base / (oraclePrice0USD / oracle0Base)
        //
        // Following SOT and sqrt spot price definition:
        //
        // sqrtOraclePriceX96 = sqrt(amount1USD / amount0USD) * 2 ** 96
        // solhint-disable-next-line max-line-length
        // = sqrt(oraclePrice0USD * token1Base * oracle1Base) * 2 ** 96 / (oraclePrice1USD * token0Base * oracle0Base)) * 2 ** 48
    }

    function getSqrtPriceX96(uint256 price0USD, uint256 price1USD) public view returns (uint160 sqrtOraclePriceX96) {
        uint256 oracle0Base = 10 ** feedToken0.decimals();
        uint256 oracle1Base = 10 ** feedToken1.decimals();
        uint256 token0Base = 10 ** token0.decimals();
        uint256 token1Base = 10 ** token1.decimals();

        uint256 oraclePriceX96 = Math.mulDiv(
            price0USD * oracle1Base * token1Base,
            1 << 96,
            price1USD * oracle0Base * token0Base
        );
        return (Math.sqrt(oraclePriceX96) << 48).toUint160();
    }
}
