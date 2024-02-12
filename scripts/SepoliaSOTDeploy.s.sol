// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import 'forge-std/Script.sol';
import { SOT } from 'src/SOT.sol';

import { SOTLiquidityProvider } from 'test/helpers/SOTLiquidityProvider.sol';

import { SOTConstructorArgs } from 'src/structs/SOTStructs.sol';

import { SOTBase } from 'test/base/SOTBase.t.sol';
import {
    SovereignPool,
    SovereignPoolBase,
    SovereignPoolConstructorArgs,
    SovereignPoolSwapParams,
    SovereignPoolSwapContextData
} from 'valantis-core/test/base/SovereignPoolBase.t.sol';

import { MockToken } from 'test/helpers/MockToken.sol';
import { SOTDeployer } from 'test/deployers/SOTDeployer.sol';
import { SovereignPoolDeployer } from 'valantis-core/test/deployers/SovereignPoolDeployer.sol';

import { AggregatorV3Interface } from 'src/vendor/chainlink/AggregatorV3Interface.sol';

contract SepoliaSOTDeployScript is Script, SOTBase {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint('SEPOLIA_PRIVATE_KEY');
        vm.startBroadcast(deployerPrivateKey);

        address signer = vm.envAddress('SEPOLIA_PUBLIC_KEY');

        MockToken token0 = new MockToken('Wrapped ETH', 'WETH', 18);
        MockToken token1 = new MockToken('USD Coin', 'USDC', 6);

        SovereignPoolConstructorArgs memory poolArgs = SovereignPoolConstructorArgs(
            address(token0),
            address(token1),
            ZERO_ADDRESS,
            vm.envAddress('SEPOLIA_PUBLIC_KEY'),
            ZERO_ADDRESS,
            ZERO_ADDRESS,
            false,
            false,
            0,
            0,
            0
        );

        // SovereignPool pool = this.deploySovereignPool(poolArgs);
        SovereignPool pool = new SovereignPool(poolArgs);

        SOTLiquidityProvider liquidityProvider = new SOTLiquidityProvider();

        AggregatorV3Interface feedToken0 = AggregatorV3Interface(vm.envAddress('SEPOLIA_ETH_USD_FEED'));
        AggregatorV3Interface feedToken1 = AggregatorV3Interface(vm.envAddress('SEPOLIA_USDC_USD_FEED'));

        SOTConstructorArgs memory sotArgs = SOTConstructorArgs({
            pool: address(pool),
            manager: vm.envAddress('SEPOLIA_PUBLIC_KEY'),
            signer: vm.envAddress('SEPOLIA_PUBLIC_KEY'),
            liquidityProvider: address(liquidityProvider),
            feedToken0: address(feedToken0),
            feedToken1: address(feedToken1),
            sqrtSpotPriceX96: getSqrtPriceX96(2300 * (10 ** feedToken0.decimals()), 1 * (10 ** feedToken1.decimals())),
            sqrtPriceLowX96: getSqrtPriceX96(1500 * (10 ** feedToken0.decimals()), 1 * (10 ** feedToken1.decimals())),
            sqrtPriceHighX96: getSqrtPriceX96(2500 * (10 ** feedToken0.decimals()), 1 * (10 ** feedToken1.decimals())),
            maxDelay: 20 minutes,
            maxOracleUpdateDurationFeed0: 1 hours,
            maxOracleUpdateDurationFeed1: 1 hours,
            solverMaxDiscountBips: 200, // 2%
            oraclePriceMaxDiffBips: 50, // 0.5%
            minAmmFeeGrowth: 100,
            maxAmmFeeGrowth: 10000,
            minAmmFee: 1 // 0.01%
        });

        SOT sot = new SOT(sotArgs);

        pool.setALM(address(sot));
        pool.setSwapFeeModule(address(sot));

        console.log('SOT deployed at: ', address(sot));

        sot.setMaxTokenVolumes(100e18, 20_000e6);
        token0.mint(address(liquidityProvider), 100e18);
        token1.mint(address(liquidityProvider), 20_000e6);
        token0.mint(address(signer), 10_000e18);
        token1.mint(address(signer), 2_000_000e6);

        liquidityProvider.setSOT(address(sot));

        vm.stopBroadcast();
    }
}
