// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import 'forge-std/Script.sol';
import { SOT } from 'src/SOT.sol';

import { MockLiquidityProvider } from 'test/mocks/MockLiquidityProvider.sol';

import { SOTConstructorArgs } from 'src/structs/SOTStructs.sol';

import { SOTBase } from 'test/base/SOTBase.t.sol';
import {
    SovereignPool,
    SovereignPoolBase,
    SovereignPoolConstructorArgs,
    SovereignPoolSwapParams,
    SovereignPoolSwapContextData
} from 'valantis-core/test/base/SovereignPoolBase.t.sol';

import { MockToken } from 'test/mocks/MockToken.sol';
import { MockChainlinkOracle } from 'test/mocks/MockChainlinkOracle.sol';

import { SOTDeployer } from 'test/deployers/SOTDeployer.sol';
import { SovereignPoolDeployer } from 'valantis-core/test/deployers/SovereignPoolDeployer.sol';

import { AggregatorV3Interface } from 'src/vendor/chainlink/AggregatorV3Interface.sol';

import { ProtocolFactory } from 'valantis-core/src/protocol-factory/ProtocolFactory.sol';
import { SovereignPoolFactory } from 'valantis-core/src/pools/factories/SovereignPoolFactory.sol';

contract GnosisSOTDeployScript is Script, SOTBase {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint('DEPLOYER_PRIVATE_KEY');
        vm.startBroadcast(deployerPrivateKey);

        address master = vm.envAddress('DEPLOYER_PUBLIC_KEY');

        address token0 = vm.envAddress('GNOSIS_TOKEN0_MOCK');
        address token1 = vm.envAddress('GNOSIS_TOKEN1_MOCK');

        SovereignPool pool = SovereignPool(vm.envAddress('GNOSIS_SOVEREIGN_POOL_MOCKS'));

        AggregatorV3Interface feedToken0 = AggregatorV3Interface(vm.envAddress('GNOSIS_USDC_USD_FEED'));
        AggregatorV3Interface feedToken1 = AggregatorV3Interface(vm.envAddress('GNOSIS_ETH_USD_FEED'));

        address liquidityProvider = vm.envAddress('GNOSIS_ARRAKIS_VALANTIS_MODULE_MOCKS');

        SOTConstructorArgs memory sotArgs = SOTConstructorArgs({
            pool: address(pool),
            manager: master,
            signer: master,
            liquidityProvider: address(liquidityProvider),
            feedToken0: address(feedToken0),
            feedToken1: address(feedToken1),
            sqrtSpotPriceX96: 1314917972337811703078981570920448, // 1/ 3600
            sqrtPriceLowX96: 1252707241875239655932069007848031, // 1/4000
            sqrtPriceHighX96: 1771595571142957102961017161607260, // 1/2000
            maxDelay: 20 minutes,
            maxOracleUpdateDurationFeed0: 24 hours,
            maxOracleUpdateDurationFeed1: 24 hours,
            solverMaxDiscountBips: 1000, // 10%
            maxOracleDeviationBound: 10000, // 100%
            minAMMFeeGrowthInPips: 1,
            maxAMMFeeGrowthInPips: 10000,
            minAMMFee: 1 // 0.01%
        });

        SOT sot = new SOT(sotArgs);

        pool.setALM(address(sot));
        pool.setSwapFeeModule(address(sot));
        pool.setPoolManager(liquidityProvider);
        sot.setMaxTokenVolumes(100e18, 20_000e6);
        sot.setMaxOracleDeviationBips(500); // 5%
        sot.setMaxAllowedQuotes(3);

        // Only for mock tokens
        // token0.mint(address(liquidityProvider), 100e18);
        // token1.mint(address(liquidityProvider), 20_000e6);
        // token0.mint(address(signer), 10_000e18);
        // token1.mint(address(signer), 2_000_000e6);

        vm.stopBroadcast();
    }
}
// 1313013659875930501843139981041065
// 1314917972337811703078981570920448
// 1771595571142957102961017161607260
// 1252707241875239655932069007848031
