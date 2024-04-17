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

contract SOTQueryScript is Script {
    function run() external {
        string memory path = DeployHelper.getPath();
        string memory json = vm.readFile(path);

        address deployerPublicKey = vm.parseJsonAddress(json, '.DeployerPublicKey');
        uint256 deployerPrivateKey = vm.envUint('DEPLOYER_PRIVATE_KEY');
        address liquidityProvider = vm.parseJsonAddress(json, '.LiquidityProvider');
        SovereignPool pool = SovereignPool(vm.parseJsonAddress(json, '.SovereignPool'));
        SOT sot = SOT(vm.parseJsonAddress(json, '.SOT'));

        AggregatorV3Interface feedToken0 = AggregatorV3Interface(vm.parseJsonAddress(json, '.FeedToken0'));
        AggregatorV3Interface feedToken1 = AggregatorV3Interface(vm.parseJsonAddress(json, '.FeedToken1'));

        address token0 = vm.parseJsonAddress(json, '.Token0');
        address token1 = vm.parseJsonAddress(json, '.Token1');

        vm.startBroadcast(deployerPrivateKey);

        (uint256 reserve0, uint256 reserve1) = pool.getReserves();
        console.log('Reserve0: ', reserve0);
        console.log('Reserve1: ', reserve1);

        vm.stopBroadcast();
    }
}
