// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.119;

import 'forge-std/Script.sol';

import { SOT } from 'src/SOT.sol';
import { SOTConstructorArgs } from 'src/structs/SOTStructs.sol';
import { SOTBase } from 'test/base/SOTBase.t.sol';
import {
    SovereignPool,
    SovereignPoolSwapParams,
    SovereignPoolSwapContextData
} from 'valantis-core/test/base/SovereignPoolBase.t.sol';

import { AggregatorV3Interface } from 'src/vendor/chainlink/AggregatorV3Interface.sol';

contract GnosisSOTDeployScript is Script, SOTBase {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint('DEPLOYER_PRIVATE_KEY');
        vm.startBroadcast(deployerPrivateKey);

        address token0 = vm.envAddress('TOKEN0');
        address token1 = vm.envAddress('TOKEN1');

        assert(token0 < token1, 'Token0 must be less than Token1');

        AggregatorV3Interface feedToken0 = AggregatorV3Interface(vm.envAddress('TOKEN0_FEED'));
        AggregatorV3Interface feedToken1 = AggregatorV3Interface(vm.envAddress('TOKEN1_FEED'));

        address manager = vm.envAddress('DEPLOYER_PUBLIC_KEY');
        address signer = vm.envAddress('DEPLOYER_PUBLIC_KEY');
        address liquidityProvider = vm.envAddress('ARRAKIS_VALANTIS_MODULE');
        SovereignPool pool = SovereignPool(vm.envAddress('SOVEREIGN_POOL'));

        uint160 sqrtSpotPriceX96 = 1314917972337811703078981570920448;
        uint160 sqrtPriceLowX96 = 1252707241875239655932069007848031;
        uint160 sqrtPriceHighX96 = 1771595571142957102961017161607260;

        SOTConstructorArgs memory sotArgs = SOTConstructorArgs({
            pool: address(pool),
            manager: manager,
            signer: signer,
            liquidityProvider: address(liquidityProvider),
            feedToken0: address(feedToken0),
            feedToken1: address(feedToken1),
            sqrtSpotPriceX96: sqrtSpotPriceX96,
            sqrtPriceLowX96: sqrtPriceLowX96,
            sqrtPriceHighX96: sqrtPriceHighX96,
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

        // Set SOT Parameters
        sot.setMaxOracleDeviationBips(500); // 5%
        sot.setMaxTokenVolumes(100 * (10 ** token0.decimals()), 20_000 * (10 ** token1.decimals()));
        sot.setMaxAllowedQuotes(3);

        assert(
            SOTParams.checkPriceDeviation(sqrtSpotPriceX96, sot.getSqrtOraclePriceX96(), sot.maxOracleDeviationBips()),
            'Invalid Spot Price or OraclePrice'
        );

        // Set SOT in the Sovereign Pool
        pool.setALM(address(sot));
        pool.setSwapFeeModule(address(sot));
        pool.setPoolManager(liquidityProvider);

        vm.stopBroadcast();
    }
}
