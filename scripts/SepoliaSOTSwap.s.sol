// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import 'forge-std/Script.sol';

import { Math } from 'valantis-core/lib/openzeppelin-contracts/contracts/utils/math/Math.sol';
import { SafeCast } from 'valantis-core/lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol';

import { SOT } from 'src/SOT.sol';
import { MockLiquidityProvider } from 'test/mocks/MockLiquidityProvider.sol';
import { SOTConstructorArgs, SolverOrderType } from 'src/structs/SOTStructs.sol';
import { SOTBase } from 'test/base/SOTBase.t.sol';
import { SOTConstants } from 'src/libraries/SOTConstants.sol';

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
    using SafeCast for uint256;

    function getSqrtPriceX96(
        MockToken token0,
        MockToken token1,
        MockChainlinkOracle feedToken0,
        MockChainlinkOracle feedToken1,
        uint256 price0USD,
        uint256 price1USD
    ) public view returns (uint160 sqrtOraclePriceX96) {
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

    function run() external {
        vm.startBroadcast(vm.envUint('SEPOLIA_PRIVATE_KEY'));

        SovereignPool pool = SovereignPool(vm.envAddress('SEPOLIA_SOVEREIGN_POOL'));
        MockToken token0 = MockToken(pool.token0());
        MockToken token1 = MockToken(pool.token1());
        MockChainlinkOracle feedToken0 = MockChainlinkOracle(vm.envAddress('SEPOLIA_ETH_USD_FEED_MOCKS'));
        MockChainlinkOracle feedToken1 = MockChainlinkOracle(vm.envAddress('SEPOLIA_USDC_USD_FEED_MOCKS'));

        SOT sot = SOT(vm.envAddress('SEPOLIA_SOT'));
        MockLiquidityProvider liquidityProvider = MockLiquidityProvider(
            vm.envAddress('SEPOLIA_SOT_LIQUIDITY_PROVIDER')
        );

        console.log('Pool address: ', address(pool));
        console.log('Token0 address: ', address(token0));
        console.log('Token1 address: ', address(token1));
        console.log('MockLiquidityProvider address: ', address(liquidityProvider));
        console.log('SOT address: ', address(sot));

        // Note: Use this to depositLiquidity and approve tokens for the pool
        // liquidityProvider.depositLiquidity(address(pool), 5e18, 10_000e6, 0, 0);

        // token0.approve(address(pool), type(uint256).max);
        // token1.approve(address(pool), type(uint256).max);

        // Note: Update these to relevant values, before making an SOT Swap. Not needed for AMM swap.
        (uint160 sqrtSpotPriceX96, , ) = sot.getAMMState();
        uint256 spotPrice = Math.mulDiv(sqrtSpotPriceX96, sqrtSpotPriceX96, 1 << 192);

        console.log('spotPriceX192: ', sqrtSpotPriceX96 * sqrtSpotPriceX96);

        feedToken0.updateAnswer((spotPrice * 1e8).toInt256());
        feedToken1.updateAnswer(1e8);

        sot.setSigner(address(this));
        SolverOrderType memory sotParams = SolverOrderType({
            amountInMax: 1e18,
            solverPriceX192Discounted: Math.mulDiv(spotPrice, 99, 100) << 192, // 1% discount
            solverPriceX192Base: Math.mulDiv(spotPrice, 9500, 10000) << 192, // 0.5% discount
            sqrtSpotPriceX96New: getSqrtPriceX96(
                token0,
                token1,
                feedToken0,
                feedToken1,
                (spotPrice + 5) * (10 ** feedToken0.decimals()),
                1 * (10 ** feedToken1.decimals())
            ), // AMM spot price 2005
            authorizedSender: address(this),
            authorizedRecipient: makeAddr('RECIPIENT'),
            signatureTimestamp: (block.timestamp).toUint32(),
            expiry: 36, // 2 Blocks
            feeMinToken0: 10, // 0.1%
            feeMaxToken0: 100, // 1%
            feeGrowthInPipsToken0: 500, // 5 bips per second
            feeMinToken1: 10,
            feeMaxToken1: 100,
            feeGrowthInPipsToken1: 500,
            nonce: 1,
            expectedFlag: 0
        });

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            vm.envUint('SEPOLIA_PRIVATE_KEY'),
            keccak256(
                abi.encodePacked(
                    '\x19\x01',
                    sot.domainSeparatorV4(),
                    keccak256(abi.encode(SOTConstants.SOT_TYPEHASH, sotParams))
                )
            )
        );

        // AMM Swap
        SovereignPoolSwapContextData memory data = SovereignPoolSwapContextData({
            externalContext: abi.encode(sotParams, abi.encodePacked(r, s, bytes1(v))),
            verifierContext: bytes(''),
            swapCallbackContext: bytes(''),
            swapFeeModuleContext: bytes('1')
        });

        console.log('block timestamp: ', block.timestamp);

        SovereignPoolSwapParams memory params = SovereignPoolSwapParams({
            isSwapCallback: false,
            isZeroToOne: false,
            amountIn: 1e18,
            amountOutMin: 0,
            recipient: address(this),
            deadline: block.timestamp + 100000, // If swaps fail, try to update this to a higher value
            swapTokenOut: address(token0),
            swapContext: data
        });

        pool.swap(params);

        vm.stopBroadcast();
    }
}
