// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import 'forge-std/Script.sol';

import { SovereignPool, SovereignPoolConstructorArgs } from 'valantis-core/test/base/SovereignPoolBase.t.sol';

import { ProtocolFactory } from 'valantis-core/src/protocol-factory/ProtocolFactory.sol';

contract SovereignPoolDeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint('DEPLOYER_PRIVATE_KEY');
        address deployerPublicKey = vm.envAddress('DEPLOYER_PUBLIC_KEY');
        address token0 = vm.envAddress('GNOSIS_TOKEN0_MOCK');
        address token1 = vm.envAddress('GNOSIS_TOKEN1_MOCK');

        ProtocolFactory protocolFactory = ProtocolFactory(vm.envAddress('PROTOCOL_FACTORY'));

        vm.startBroadcast(deployerPrivateKey);

        SovereignPoolConstructorArgs memory poolArgs = SovereignPoolConstructorArgs({
            token0: token0,
            token1: token1,
            protocolFactory: address(protocolFactory),
            poolManager: master,
            sovereignVault: ZERO_ADDRESS,
            verifierModule: ZERO_ADDRESS,
            isToken0Rebase: false,
            isToken1Rebase: false,
            token0AbsErrorTolerance: 0,
            token1AbsErrorTolerance: 0,
            defaultSwapFeeBips: 0
        });

        SovereignPool pool = SovereignPool(protocolFactory.deploySovereignPool(poolArgs));

        vm.stopBroadcast();
    }
}
