// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import 'forge-std/Script.sol';

import { ProtocolFactory } from 'valantis-core/src/protocol-factory/ProtocolFactory.sol';
import { SovereignPoolFactory } from 'valantis-core/src/pools/factories/SovereignPoolFactory.sol';

contract ProtocolFactoryDeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint('DEPLOYER_PRIVATE_KEY');
        address deployerPublicKey = vm.envAddress('DEPLOYER_PUBLIC_KEY');

        vm.startBroadcast(deployerPrivateKey);

        ProtocolFactory protocolFactory = new ProtocolFactory(
            deployerPublicKey,
            uint32(vm.envUint('CHAIN_BLOCK_TIME'))
        );
        SovereignPoolFactory sovereignPoolFactory = new SovereignPoolFactory();
        protocolFactory.setSovereignPoolFactory(address(sovereignPoolFactory));

        vm.writeJson('my new string', './deployments/100.json', '.test');

        vm.stopBroadcast();
    }
}
