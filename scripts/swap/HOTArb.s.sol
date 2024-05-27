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

contract HOTArbScript is Script {
    function run() external {
        string memory path = DeployHelper.getPath();
        string memory json = vm.readFile(path);

        uint256 arbPrivateKey = vm.envUint('ARB_PRIVATE_KEY');

        SovereignPool pool = SovereignPool(vm.parseJsonAddress(json, '.SovereignPool'));
        HOT hot = HOT(vm.parseJsonAddress(json, '.HOT'));

        address token0 = vm.parseJsonAddress(json, '.Token0');
        address token1 = vm.parseJsonAddress(json, '.Token1');

        vm.startBroadcast(arbPrivateKey);

        bool isArb;
        uint256 reserve0;
        uint256 reserve1;
        uint160 sqrtOraclePriceX96;

        {
            (uint160 sqrtPriceX96, uint160 sqrtPriceLowerX96, uint160 sqrtPriceUpperX96) = hot.getAMMState();

            console.log('sqrtSpotPrice: ', sqrtPriceX96);
            console.log('sqrtPriceLow: ', sqrtPriceLowerX96);
            console.log('sqrtPriceHigh: ', sqrtPriceUpperX96);

            sqrtOraclePriceX96 = hot.getSqrtOraclePriceX96();
            console.log('sqrtOraclePriceX96: ', sqrtOraclePriceX96);

            (reserve0, reserve1) = pool.getReserves();
            console.log('Reserve0: ', reserve0);
            console.log('Reserve1: ', reserve1);

            (, , uint16 maxOracleDeviationBipsLower, uint16 maxOracleDeviationBipsUpper, , , ) = hot.hotReadSlot();

            console.log('maxOracleDeviationBipsLower: ', maxOracleDeviationBipsLower);
            console.log('maxOracleDeviationBipsUpper: ', maxOracleDeviationBipsUpper);

            isArb = !HOTParams.checkPriceDeviation(
                sqrtPriceX96,
                sqrtOraclePriceX96,
                maxOracleDeviationBipsLower,
                maxOracleDeviationBipsUpper
            );
            console.log('check deviation passed: ', !isArb);
        }

        if (isArb) {
            SovereignPoolSwapContextData memory data;

            (uint256 reserve0Expected, uint256 reserve1Expected) = hot.getReservesAtPrice(sqrtOraclePriceX96);

            SovereignPoolSwapParams memory params;

            params.isZeroToOne = reserve0Expected > reserve0 ? true : false;
            params.amountIn = reserve0Expected > reserve0 ? reserve0Expected - reserve0 : reserve1Expected - reserve1;
            params.recipient = vm.addr(arbPrivateKey);
            params.deadline = block.timestamp + 100;
            params.swapTokenOut = params.isZeroToOne ? token1 : token0;
            params.swapContext = data;

            pool.swap(params);
        }

        (uint160 sqrtSpotPriceX96New, , ) = hot.getAMMState();

        console.log('sqrtSpotPriceNew : ', sqrtSpotPriceX96New);

        vm.stopBroadcast();
    }
}
