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

contract HOTAMMDeployScript is Script {
    error HOTAMMDeployScript__token0GteToken1();

    function run() external {
        string memory path = DeployHelper.getPath();
        string memory json = vm.readFile(path);

        uint256 deployerPrivateKey = vm.envUint('DEPLOYER_PRIVATE_KEY');
        address deployerPublicKey = vm.addr(deployerPrivateKey);

        SovereignPool pool = SovereignPool(vm.parseJsonAddress(json, '.SovereignPool'));

        address token0 = vm.parseJsonAddress(json, '.Token0');
        address token1 = vm.parseJsonAddress(json, '.Token1');

        vm.startBroadcast(deployerPrivateKey);

        if (token0 >= token1) {
            revert HOTAMMDeployScript__token0GteToken1();
        }

        uint160 sqrtSpotPriceX96 = 3961408125713217069514752;

        HOT hot;
        {
            uint160 sqrtPriceLowX96 = 3543191142285914327220224;
            uint160 sqrtPriceHighX96 = 4339505179874779662909440;

            HOTParams.validatePriceBounds(sqrtSpotPriceX96, sqrtPriceLowX96, sqrtPriceHighX96);

            HOTConstructorArgs memory hotArgs = HOTConstructorArgs({
                pool: address(pool),
                manager: deployerPublicKey,
                signer: deployerPublicKey,
                liquidityProvider: deployerPublicKey,
                feedToken0: address(0),
                feedToken1: address(0),
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

        // Set HOT in the Sovereign Pool
        pool.setALM(address(hot));
        pool.setSwapFeeModule(address(hot));

        vm.writeJson(Strings.toHexString(address(hot)), path, '.HOT');

        vm.stopBroadcast();
    }
}
