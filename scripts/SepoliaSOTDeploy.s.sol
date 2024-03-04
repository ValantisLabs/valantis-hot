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

contract SepoliaSOTDeployScript is Script, SOTBase {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint('SEPOLIA_PRIVATE_KEY');
        vm.startBroadcast(deployerPrivateKey);

        address signer = vm.envAddress('SEPOLIA_PUBLIC_KEY');
        address weth = vm.envAddress('SEPOLIA_WETH_REAL');
        address mockToken0 = vm.envAddress('SEPOLIA_TOKEN0_MOCK');
        address mockToken1 = vm.envAddress('SEPOLIA_TOKEN1_MOCK');

        // MockToken token0 = new MockToken('Wrapped ETH', 'WETH', 18);
        // MockToken token1 = new MockToken('USD Coin', 'USDC', 6);

        // SovereignPoolConstructorArgs memory poolArgs = SovereignPoolConstructorArgs(
        //     address(mockToken0),
        //     address(mockToken1),
        //     ZERO_ADDRESS,
        //     vm.envAddress('SEPOLIA_PUBLIC_KEY'),
        //     ZERO_ADDRESS,
        //     ZERO_ADDRESS,
        //     false,
        //     false,
        //     0,
        //     0,
        //     0
        // );

        // SovereignPool pool = new SovereignPool(poolArgs);

        SovereignPool pool = SovereignPool(vm.envAddress('SEPOLIA_SOVEREIGN_POOL_MOCKS'));
        // SovereignPool pool = SovereignPool(vm.envAddress('SEPOLIA_SOVEREIGN_POOL_WETH'));

        // MockLiquidityProvider liquidityProvider = new MockLiquidityProvider();

        // AggregatorV3Interface feedToken0 = AggregatorV3Interface(vm.envAddress('SEPOLIA_ETH_USD_FEED'));
        // AggregatorV3Interface feedToken1 = AggregatorV3Interface(vm.envAddress('SEPOLIA_USDC_USD_FEED'));

        address liquidityProvider = vm.envAddress('SEPOLIA_ARRAKIS_VALANTIS_MODULE_MOCKS');
        // address liquidityProvider = vm.envAddress('SEPOLIA_ARRAKIS_VALANTIS_MODULE_WETH');

        // AggregatorV3Interface feedToken0 = new MockChainlinkOracle(8);
        // AggregatorV3Interface feedToken1 = new MockChainlinkOracle(8);
        // SOTConstructorArgs memory sotArgs = SOTConstructorArgs({
        //     pool: address(pool),
        //     manager: vm.envAddress('SEPOLIA_PUBLIC_KEY'),
        //     signer: vm.envAddress('SEPOLIA_PUBLIC_KEY'),
        //     liquidityProvider: address(liquidityProvider),
        //     feedToken0: address(feedToken0),
        //     feedToken1: address(feedToken1),
        //     sqrtSpotPriceX96: getSqrtPriceX96(2300 * (10 ** feedToken0.decimals()), 1 * (10 ** feedToken1.decimals())),
        //     sqrtPriceLowX96: getSqrtPriceX96(1500 * (10 ** feedToken0.decimals()), 1 * (10 ** feedToken1.decimals())),
        //     sqrtPriceHighX96: getSqrtPriceX96(2500 * (10 ** feedToken0.decimals()), 1 * (10 ** feedToken1.decimals())),
        //     maxDelay: 20 minutes,
        //     maxOracleUpdateDurationFeed0: 1 hours,
        //     maxOracleUpdateDurationFeed1: 1 hours,
        //     solverMaxDiscountBips: 200, // 2%
        //     maxOracleDeviationBound: 50, // 0.5%
        //     minAMMFeeGrowthInPips: 100,
        //     maxAMMFeeGrowthInPips: 10000,
        //     minAMMFee: 1 // 0.01%
        // });

        // SOT sot = new SOT(sotArgs);

        // pool.setALM(address(sot));
        // pool.setSwapFeeModule(address(sot));

        pool.setPoolManager(liquidityProvider);

        // console.log('SOT deployed at: ', address(sot));

        // sot.setMaxTokenVolumes(100e18, 20_000e6);
        // token0.mint(address(liquidityProvider), 100e18);
        // token1.mint(address(liquidityProvider), 20_000e6);
        // token0.mint(address(signer), 10_000e18);
        // token1.mint(address(signer), 2_000_000e6);

        // liquidityProvider.setSOT(address(sot));

        vm.stopBroadcast();
    }
}
