// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import 'forge-std/Script.sol';

import { SOT } from 'src/SOT.sol';
import { SOTParams } from 'src/libraries/SOTParams.sol';
import { SOTConstructorArgs } from 'src/structs/SOTStructs.sol';
import { SOTBase } from 'test/base/SOTBase.t.sol';
import {
    SovereignPool,
    SovereignPoolSwapParams,
    SovereignPoolSwapContextData
} from 'valantis-core/test/base/SovereignPoolBase.t.sol';

import { AggregatorV3Interface } from 'src/vendor/chainlink/AggregatorV3Interface.sol';
import { DeployHelper } from 'scripts/utils/DeployHelper.sol';
import { Strings } from 'valantis-core/lib/openzeppelin-contracts/contracts/utils/Strings.sol';
import { ERC20 } from 'valantis-core/lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol';

contract SOTDeployScript is Script {
    error SOTDeployScript__oraclePriceDeviation();
    error SOTDeployScript__token0GteToken1();

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
            revert SOTDeployScript__token0GteToken1();
        }

        uint160 sqrtSpotPriceX96 = 4358039060504156305358848;

        SOT sot;
        {
            uint160 sqrtPriceLowX96 = 4339505179874779489431521;
            uint160 sqrtPriceHighX96 = 5010828967500958623728276;

            SOTParams.validatePriceBounds(sqrtSpotPriceX96, sqrtPriceLowX96, sqrtPriceHighX96);

            SOTConstructorArgs memory sotArgs = SOTConstructorArgs({
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
                solverMaxDiscountBips: 1000, // 10%
                maxOracleDeviationBound: 10000, // 100%
                minAMMFeeGrowthE6: 1,
                maxAMMFeeGrowthE6: 10000,
                minAMMFee: 1 // 0.01%
            });

            sot = new SOT(sotArgs);
        }

        {
            // Customize according to each token pair
            uint256 token0MaxVolume = 100 * (10 ** ERC20(token0).decimals());
            uint256 token1MaxVolume = 20_000 * (10 ** ERC20(token1).decimals());

            // Set SOT Parameters
            sot.setMaxOracleDeviationBips(500); // 5%
            sot.setMaxTokenVolumes(token0MaxVolume, token1MaxVolume);
            sot.setMaxAllowedQuotes(3);
        }

        (, , uint16 maxOracleDeviationBipsLower, uint16 maxOracleDeviationBipsUpper, , , ) = sot.solverReadSlot();

        if (
            !SOTParams.checkPriceDeviation(
                sqrtSpotPriceX96,
                sot.getSqrtOraclePriceX96(),
                maxOracleDeviationBipsLower,
                maxOracleDeviationBipsUpper
            )
        ) {
            revert SOTDeployScript__oraclePriceDeviation();
        }

        // Set SOT in the Sovereign Pool
        pool.setALM(address(sot));
        pool.setSwapFeeModule(address(sot));
        pool.setPoolManager(liquidityProvider);

        vm.writeJson(Strings.toHexString(address(sot)), path, '.SOT');

        vm.stopBroadcast();
    }
}
