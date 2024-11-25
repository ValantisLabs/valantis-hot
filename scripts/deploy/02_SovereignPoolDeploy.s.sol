// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import 'forge-std/Script.sol';

import { SovereignPool, SovereignPoolConstructorArgs } from 'valantis-core/test/base/SovereignPoolBase.t.sol';
import { SovereignPoolFactory } from 'valantis-core/src/pools/factories/SovereignPoolFactory.sol';
import { ProtocolFactory } from 'valantis-core/src/protocol-factory/ProtocolFactory.sol';
import { Strings } from 'valantis-core/lib/openzeppelin-contracts/contracts/utils/Strings.sol';

import { DeployHelper } from 'scripts/utils/DeployHelper.sol';

contract SovereignPoolDeployScript is Script {
    error SovereignPoolDeployScript__token0GteToken1();

    function run() external {
        string memory path = DeployHelper.getPath();
        string memory json = vm.readFile(path);

        uint256 deployerPrivateKey = vm.envUint('DEPLOYER_PRIVATE_KEY');
        address deployerAddress = vm.addr(deployerPrivateKey);

        address token0 = vm.parseJsonAddress(json, '.Token0');
        address token1 = vm.parseJsonAddress(json, '.Token1');

        if (token0 >= token1) {
            revert SovereignPoolDeployScript__token0GteToken1();
        }

        ProtocolFactory protocolFactory = ProtocolFactory(vm.parseJsonAddress(json, '.ProtocolFactory'));

        vm.startBroadcast(deployerPrivateKey);

        SovereignPoolConstructorArgs memory poolArgs = SovereignPoolConstructorArgs({
            token0: token0,
            token1: token1,
            protocolFactory: address(protocolFactory),
            poolManager: deployerAddress,
            sovereignVault: address(0),
            verifierModule: address(0),
            isToken0Rebase: false,
            isToken1Rebase: false,
            token0AbsErrorTolerance: 0,
            token1AbsErrorTolerance: 0,
            defaultSwapFeeBips: 0
        });

        address pool = protocolFactory.deploySovereignPool(poolArgs);

        vm.writeJson(Strings.toHexString(pool), path, '.SovereignPool');

        vm.stopBroadcast();
    }
}
