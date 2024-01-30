// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { SOT } from 'src/SOT.sol';
import { SOTConstructorArgs } from 'src/structs/SOTStructs.sol';

library SOTFactoryLibDeploy {
    /************************************************
     *  CUSTOM ERRORS
     ***********************************************/

    error MockSovereignALMFactory__deploy_invalidDeployer();

    /************************************************
     *  FUNCTIONS
     ***********************************************/

    function deploy(
        bytes32 _salt,
        bytes calldata _constructorArgs,
        address protocolFactory
    ) external returns (address deployment) {
        if (msg.sender != protocolFactory) {
            revert MockSovereignALMFactory__deploy_invalidDeployer();
        }

        SOTConstructorArgs memory args = abi.decode(_constructorArgs, (SOTConstructorArgs));
        deployment = address(new SOT{ salt: _salt }(args));
    }
}
