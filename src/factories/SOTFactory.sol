// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { IValantisDeployer } from 'valantis-core/src/protocol-factory/interfaces/IValantisDeployer.sol';

import { SOT } from 'src/SOT.sol';
import { SOTFactoryLibDeploy } from 'src/libraries/SOTFactoryLibDeploy.sol';
import { SOTFactoryLibAddress } from 'src/libraries/SOTFactoryLibAddress.sol';

contract SOTFactory is IValantisDeployer {
    /************************************************
     *  IMMUTABLES
     ***********************************************/

    address public immutable protocolFactory;

    /************************************************
     *  CONSTRUCTOR
     ***********************************************/

    constructor(address _protocolFactory) {
        protocolFactory = _protocolFactory;
    }

    /************************************************
     *  EXTERNAL FUNCTIONS
     ***********************************************/

    function getCreate2Address(bytes32 _salt, bytes calldata _constructorArgs) external view returns (address) {
        return SOTFactoryLibAddress.getCreate2Address(_salt, _constructorArgs);
    }

    function deploy(bytes32 _salt, bytes calldata _constructorArgs) external override returns (address deployment) {
        return SOTFactoryLibDeploy.deploy(_salt, _constructorArgs, protocolFactory);
    }
}
