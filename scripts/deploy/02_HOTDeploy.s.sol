// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import 'forge-std/Script.sol';

import { HOT } from 'src/HOT.sol';
import { HOTParams } from 'src/libraries/HOTParams.sol';
import { HOTConstructorArgs } from 'src/structs/HOTStructs.sol';
import { HOTBase } from 'test/base/HOTBase.t.sol';
import {
    SovereignPool,
    SovereignPoolSwapParams,
    SovereignPoolSwapContextData
} from 'valantis-core/test/base/SovereignPoolBase.t.sol';

import { AggregatorV3Interface } from 'src/vendor/chainlink/AggregatorV3Interface.sol';
import { DeployHelper } from 'scripts/utils/DeployHelper.sol';
import { Strings } from 'valantis-core/lib/openzeppelin-contracts/contracts/utils/Strings.sol';
import { ERC20 } from 'valantis-core/lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol';

contract HOTDeployScript is Script {
    error HOTDeployScript__oraclePriceDeviation();
    error HOTDeployScript__token0GteToken1();

    function run() external {
        string memory path = DeployHelper.getPath();
        string memory json = vm.readFile(path);

        address deployerPublicKey = vm.parseJsonAddress(json, '.DeployerPublicKey');
        uint256 deployerPrivateKey = vm.envUint('DEPLOYER_PRIVATE_KEY');
        address liquidityProvider = vm.parseJsonAddress(json, '.LiquidityProvider');
        SovereignPool pool = SovereignPool(vm.parseJsonAddress(json, '.SovereignPool'));

        AggregatorV3Interface feedToken0 = AggregatorV3Interface(vm.parseJsonAddress(json, '.FeedToken0'));
        AggregatorV3Interface feedToken1 = AggregatorV3Interface(vm.parseJsonAddress(json, '.FeedToken1'));

        address token0 = vm.parseJsonAddress(json, '.Token0');
        address token1 = vm.parseJsonAddress(json, '.Token1');

        vm.startBroadcast(deployerPrivateKey);

        if (token0 >= token1) {
            revert HOTDeployScript__token0GteToken1();
        }

        uint160 sqrtSpotPriceX96 = 4358039060504156305358848;

        HOT hot;
        {
            uint160 sqrtPriceLowX96 = 4339505179874779489431521;
            uint160 sqrtPriceHighX96 = 5010828967500958623728276;

            HOTParams.validatePriceBounds(sqrtSpotPriceX96, sqrtPriceLowX96, sqrtPriceHighX96);

            HOTConstructorArgs memory hotArgs = HOTConstructorArgs({
                pool: address(pool),
                manager: deployerPublicKey,
                signer: deployerPublicKey,
                liquidityProvider: address(liquidityProvider),
                feedToken0: address(feedToken0),
                feedToken1: address(feedToken1),
                sqrtSpotPriceX96: sqrtSpotPriceX96,
                sqrtPriceLowX96: sqrtPriceLowX96,
                sqrtPriceHighX96: sqrtPriceHighX96,
                maxDelay: 20 minutes,
                maxOracleUpdateDurationFeed0: 24 hours,
                maxOracleUpdateDurationFeed1: 24 hours,
                hotMaxDiscountBips: 1000, // 10%
                maxOracleDeviationBound: 10000, // 100%
                minAMMFeeGrowthE6: 1,
                maxAMMFeeGrowthE6: 10000,
                minAMMFee: 1 // 0.01%
            });

            hot = new HOT(hotArgs);
        }

        {
            // Customize according to each token pair
            uint256 token0MaxVolume = 100 * (10 ** ERC20(token0).decimals());
            uint256 token1MaxVolume = 20_000 * (10 ** ERC20(token1).decimals());

            // Set HOT Parameters
            hot.setMaxOracleDeviationBips(500); // 5%
            hot.setMaxTokenVolumes(token0MaxVolume, token1MaxVolume);
            hot.setMaxAllowedQuotes(3);
        }

        (, , uint16 maxOracleDeviationBipsLower, uint16 maxOracleDeviationBipsUpper, , , ) = hot.hotReadSlot();

        if (
            !HOTParams.checkPriceDeviation(
                sqrtSpotPriceX96,
                hot.getSqrtOraclePriceX96(),
                maxOracleDeviationBipsLower,
                maxOracleDeviationBipsUpper
            )
        ) {
            revert HOTDeployScript__oraclePriceDeviation();
        }

        // Set HOT in the Sovereign Pool
        pool.setALM(address(hot));
        pool.setSwapFeeModule(address(hot));
        pool.setPoolManager(liquidityProvider);

        vm.writeJson(Strings.toHexString(address(hot)), path, '.HOT');

        vm.stopBroadcast();
    }
}
