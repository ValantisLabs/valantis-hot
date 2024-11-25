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

        uint256 deployerPrivateKey = vm.envUint('DEPLOYER_PRIVATE_KEY');
        address protocolDeployer = vm.envAddress('PROTOCOL_DEPLOYER_ADDRESS');

        vm.startBroadcast(deployerPrivateKey);

        ProtocolFactory protocolFactory = new ProtocolFactory(protocolDeployer);

        vm.writeJson(Strings.toHexString(address(protocolFactory)), path, '.ProtocolFactory');

        vm.stopBroadcast();
    }
}
