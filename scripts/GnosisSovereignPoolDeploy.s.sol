// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import 'forge-std/Script.sol';
import { SOT } from 'src/SOT.sol';

import { MockLiquidityProvider } from 'test/mocks/MockLiquidityProvider.sol';

import { SOTConstructorArgs } from 'src/structs/SOTStructs.sol';

import { SOTBase } from 'test/base/SOTBase.t.sol';
import {
    SovereignPool,
    SovereignPoolBase,
    SovereignPoolConstructorArgs,
    SovereignPoolSwapParams,
    SovereignPoolSwapContextData
} from 'valantis-core/test/base/SovereignPoolBase.t.sol';

import { MockToken } from 'test/mocks/MockToken.sol';
import { MockChainlinkOracle } from 'test/mocks/MockChainlinkOracle.sol';

import { SOTDeployer } from 'test/deployers/SOTDeployer.sol';
import { SovereignPoolDeployer } from 'valantis-core/test/deployers/SovereignPoolDeployer.sol';

import { AggregatorV3Interface } from 'src/vendor/chainlink/AggregatorV3Interface.sol';

import { ProtocolFactory } from 'valantis-core/src/protocol-factory/ProtocolFactory.sol';
import { SovereignPoolFactory } from 'valantis-core/src/pools/factories/SovereignPoolFactory.sol';

contract GnosisSovereignPoolDeployScript is Script, SOTBase {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint('DEPLOYER_PRIVATE_KEY');
        vm.startBroadcast(deployerPrivateKey);

        address master = vm.envAddress('DEPLOYER_PUBLIC_KEY');

        address token0 = vm.envAddress('GNOSIS_TOKEN0_MOCK');
        address token1 = vm.envAddress('GNOSIS_TOKEN1_MOCK');

        // ProtocolFactory protocolFactory = new ProtocolFactory(master, uint32(vm.envUint('GNOSIS_BLOCK_TIME')));
        // SovereignPoolFactory sovereignPoolFactory = new SovereignPoolFactory();
        // protocolFactory.setSovereignPoolFactory(address(sovereignPoolFactory));

        ProtocolFactory protocolFactory = ProtocolFactory(vm.envAddress('GNOSIS_PROTOCOL_FACTORY'));

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
