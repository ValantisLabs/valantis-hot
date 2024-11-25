// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import 'forge-std/Script.sol';

import { Strings } from 'valantis-core/lib/openzeppelin-contracts/contracts/utils/Strings.sol';
import { ERC20 } from 'valantis-core/lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol';
import {
    SovereignPool,
    SovereignPoolSwapParams,
    SovereignPoolSwapContextData
} from 'valantis-core/test/base/SovereignPoolBase.t.sol';

import { AggregatorV3Interface } from 'src/vendor/chainlink/AggregatorV3Interface.sol';
import { DeployHelper } from 'scripts/utils/DeployHelper.sol';
import { HOT } from 'src/HOT.sol';
import { HOTParams } from 'src/libraries/HOTParams.sol';
import { HOTConstructorArgs } from 'src/structs/HOTStructs.sol';
import { HOTBase } from 'test/base/HOTBase.t.sol';

contract HOTDeployScript is Script {
    error HOTDeployScript__oraclePriceDeviation(uint160 sqrtSpotPriceX96, uint160 sqrtOraclePriceX96);
    error HOTDeployScript__token0GteToken1();

    function run() external {
        string memory path = DeployHelper.getPath();
        string memory json = vm.readFile(path);

        uint256 deployerPrivateKey = vm.envUint('DEPLOYER_PRIVATE_KEY');
        address deployerAddress = vm.addr(deployerPrivateKey);

        SovereignPool pool = SovereignPool(vm.parseJsonAddress(json, '.SovereignPool'));

        AggregatorV3Interface feedToken0 = AggregatorV3Interface(vm.parseJsonAddress(json, '.FeedToken0'));
        AggregatorV3Interface feedToken1 = AggregatorV3Interface(vm.parseJsonAddress(json, '.FeedToken1'));

        address liquidityProvider = vm.parseJsonAddress(json, '.LiquidityProvider');

        address token0 = vm.parseJsonAddress(json, '.Token0');
        address token1 = vm.parseJsonAddress(json, '.Token1');

        address signer = vm.parseJsonAddress(json, '.HOTSigner');

        vm.startBroadcast(deployerPrivateKey);

        if (token0 >= token1) {
            revert HOTDeployScript__token0GteToken1();
        }

        HOT hot;
        {
            // Reuse sqrt prices for new HOT deployment,
            // Input values manually in case this is not an option
            //HOT hotOldDeployment = HOT(0xf237851D574774E451ee8868314a6eA031C20CDe);
            //(uint160 sqrtSpotPriceX96, uint160 sqrtPriceLowX96, uint160 sqrtPriceHighX96) = hotOldDeployment
            //    .getAMMState();
            uint160 sqrtSpotPriceX96 = 3956662449992349527907404;
            uint160 sqrtPriceLowX96 = 3687169404161216048371746;
            uint160 sqrtPriceHighX96 = 5222629596515999476642522;

            HOTParams.validatePriceBounds(sqrtSpotPriceX96, sqrtPriceLowX96, sqrtPriceHighX96);

            HOTConstructorArgs memory hotArgs = HOTConstructorArgs({
                pool: address(pool),
                manager: deployerAddress, // optional in AMM only mode
                signer: signer, // set to address(0) for AMM only mode
                liquidityProvider: address(liquidityProvider),
                feedToken0: address(feedToken0), // set to address(0) for AMM only mode
                feedToken1: address(feedToken1), // set to address(0) for AMM only mode
                sqrtSpotPriceX96: sqrtSpotPriceX96,
                sqrtPriceLowX96: sqrtPriceLowX96,
                sqrtPriceHighX96: sqrtPriceHighX96,
                maxDelay: 20 minutes,
                maxOracleUpdateDurationFeed0: 24 hours,
                maxOracleUpdateDurationFeed1: 24 hours,
                hotMaxDiscountBipsLower: 1000, // 10%
                hotMaxDiscountBipsUpper: 1000, // 10%
                maxOracleDeviationBound: 10000, // 100%
                minAMMFeeGrowthE6: 0,
                maxAMMFeeGrowthE6: 10000,
                minAMMFee: 1 // 0.01%
            });

            hot = new HOT(hotArgs);
        }

        // Ignore in AMM only mode
        {
            // Customize according to each token pair
            uint256 token0MaxVolume = 100 * (10 ** ERC20(token0).decimals());
            uint256 token1MaxVolume = 20_000 * (10 ** ERC20(token1).decimals());

            // Set HOT Parameters
            hot.setMaxOracleDeviationBips(1000, 1000); // 10%
            hot.setMaxTokenVolumes(token0MaxVolume, token1MaxVolume);
            hot.setMaxAllowedQuotes(3);
        }

        // Ignore in AMM only mode
        {
            (, , uint16 maxOracleDeviationBipsLower, uint16 maxOracleDeviationBipsUpper, , , ) = hot.hotReadSlot();
            (uint160 sqrtSpotPriceX96, , ) = hot.getAMMState();
            if (
                !HOTParams.checkPriceDeviation(
                    sqrtSpotPriceX96,
                    hot.getSqrtOraclePriceX96(),
                    maxOracleDeviationBipsLower,
                    maxOracleDeviationBipsUpper
                )
            ) {
                revert HOTDeployScript__oraclePriceDeviation(sqrtSpotPriceX96, hot.getSqrtOraclePriceX96());
            }
        }

        // Ignore in AMM only mode
        {
            address hotManager = vm.parseJsonAddress(json, '.HOTManager');
            // Set HOT manager
            hot.setManager(hotManager);
        }

        // Set HOT as Liquidity Module and Swap Fee Module in the Sovereign Pool
        pool.setALM(address(hot));
        pool.setSwapFeeModule(address(hot));
        // Set Pool Manager as liquidityProvider
        pool.setPoolManager(liquidityProvider);

        vm.writeJson(Strings.toHexString(address(hot)), path, '.HOT');

        vm.stopBroadcast();
    }
}
