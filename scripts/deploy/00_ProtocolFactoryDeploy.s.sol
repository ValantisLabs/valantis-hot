// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import 'forge-std/Script.sol';

import { ProtocolFactory } from 'valantis-core/src/protocol-factory/ProtocolFactory.sol';
import { SovereignPoolFactory } from 'valantis-core/src/pools/factories/SovereignPoolFactory.sol';
import { Strings } from 'valantis-core/lib/openzeppelin-contracts/contracts/utils/Strings.sol';
import { DeployHelper } from 'scripts/utils/DeployHelper.sol';

contract ProtocolFactoryDeployScript is Script {
    function run() external {
        string memory path = DeployHelper.getPath();
        string memory json = vm.readFile(path);

        uint256 deployerPrivateKey = vm.envUint('DEPLOYER_PRIVATE_KEY');
        address deployerPublicKey = vm.parseJsonAddress(json, '.DeployerPublicKey');

        vm.startBroadcast(deployerPrivateKey);

        ProtocolFactory protocolFactory = new ProtocolFactory(
            deployerPublicKey,
            uint32(vm.parseJsonUint(json, '.ChainID'))
        );
        SovereignPoolFactory sovereignPoolFactory = new SovereignPoolFactory();
        protocolFactory.setSovereignPoolFactory(address(sovereignPoolFactory));

        vm.writeJson(Strings.toHexString(address(protocolFactory)), path, '.ProtocolFactory');
        vm.writeJson(Strings.toHexString(address(sovereignPoolFactory)), path, '.SovereignPoolFactory');

        vm.stopBroadcast();
    }
}
