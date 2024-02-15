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

import { MockToken } from 'test/mocks/MockToken.sol';
import { MockChainlinkOracle } from 'test/mocks/MockChainlinkOracle.sol';
import { SOTDeployer } from 'test/deployers/SOTDeployer.sol';
import { SovereignPoolDeployer } from 'valantis-core/test/deployers/SovereignPoolDeployer.sol';

import { AggregatorV3Interface } from 'src/vendor/chainlink/AggregatorV3Interface.sol';

contract SepoliaSOTSwapScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint('SEPOLIA_PRIVATE_KEY');
        vm.startBroadcast(deployerPrivateKey);

        SovereignPool pool = SovereignPool(vm.envAddress('SEPOLIA_SOVEREIGN_POOL'));
        MockToken token0 = MockToken(pool.token0());
        MockToken token1 = MockToken(pool.token1());
        MockChainlinkOracle feedToken0 = MockChainlinkOracle(vm.envAddress('SEPOLIA_ETH_USD_FEED'));
        MockChainlinkOracle feedToken1 = MockChainlinkOracle(vm.envAddress('SEPOLIA_USDC_USD_FEED'));

        SOT sot = SOT(vm.envAddress('SEPOLIA_SOT'));
        SOTLiquidityProvider liquidityProvider = SOTLiquidityProvider(vm.envAddress('SEPOLIA_SOT_LIQUIDITY_PROVIDER'));

        console.log('Pool address: ', address(pool));
        console.log('Token0 address: ', address(token0));
        console.log('Token1 address: ', address(token1));
        console.log('SOTLiquidityProvider address: ', address(liquidityProvider));
        console.log('SOT address: ', address(sot));

        liquidityProvider.depositLiquidity(address(pool), 5e18, 10_000e6, 0, 0);

        token0.approve(address(pool), type(uint256).max);
        token1.approve(address(pool), type(uint256).max);

        // Note: Update these to relevant values, before making an SOT Swap. Not needed for AMM swap.
        // feedToken0.updateAnswer(2000e8);
        // feedToken1.updateAnswer(1e8);

        // AMM Swap
        SovereignPoolSwapContextData memory data = SovereignPoolSwapContextData({
            externalContext: bytes(''),
            verifierContext: bytes(''),
            swapCallbackContext: bytes(''),
            swapFeeModuleContext: bytes('')
        });

        console.log('block timestamp: ', block.timestamp);

        SovereignPoolSwapParams memory params = SovereignPoolSwapParams({
            isSwapCallback: false,
            isZeroToOne: true,
            amountIn: 1e18,
            amountOutMin: 0,
            recipient: address(this),
            deadline: block.timestamp + 100000, // If swaps fail, try to update this to a higher value
            swapTokenOut: address(token1),
            swapContext: data
        });

        pool.swap(params);

        vm.stopBroadcast();
    }
}
