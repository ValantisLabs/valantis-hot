// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {
    SovereignPoolDeployer,
    ProtocolFactory,
    SovereignPoolConstructorArgs,
    SovereignPool
} from 'valantis-core/test/deployers/SovereignPoolDeployer.sol';

import { SOTConstructorArgs } from 'src/structs/SOTStructs.sol';
import { SOTFactory } from 'src/factories/SOTFactory.sol';
import { SOT } from 'src/SOT.sol';

contract SOTDeployer {
    function deploySOT(SovereignPool _sovereignPool, SOTConstructorArgs memory _sotArgs) public returns (SOT sot) {
        sot = _deploySOT(ProtocolFactory(_sovereignPool.protocolFactory()), _sovereignPool, _sotArgs);
    }

    function _deploySOT(
        ProtocolFactory protocolFactory,
        SovereignPool sovereignPool,
        SOTConstructorArgs memory sotArgs
    ) internal returns (SOT sot) {
        SOTFactory sotFactory = new SOTFactory(address(protocolFactory));
        protocolFactory.addSovereignALMFactory(address(sotFactory));

        sot = SOT(
            protocolFactory.deployALMPositionForSovereignPool(
                address(sovereignPool),
                address(sotFactory),
                abi.encode(sotArgs)
            )
        );

        sovereignPool.setALM(address(sot));
        sovereignPool.setSwapFeeModule(address(sot));
    }
}
