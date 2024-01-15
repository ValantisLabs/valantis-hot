// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { IValantisDeployer } from 'valantis-core/src/protocol-factory/interfaces/IValantisDeployer.sol';

import { SOTConstructorArgs } from 'src/structs/SOTStructs.sol';
import { SOT } from 'src/SOT.sol';

contract SOTFactory is IValantisDeployer {
    /************************************************
     *  CUSTOM ERRORS
     ***********************************************/

    error MockSovereignALMFactory__deploy_invalidDeployer();

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
        bool hasConstructorArgs = keccak256(_constructorArgs) != keccak256(new bytes(0));

        bytes32 create2Hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                address(this),
                _salt,
                keccak256(
                    hasConstructorArgs
                        ? abi.encodePacked(type(SOT).creationCode, _constructorArgs)
                        : type(SOT).creationCode
                )
            )
        );

        return address(uint160(uint256(create2Hash)));
    }

    function deploy(bytes32 _salt, bytes calldata _constructorArgs) external override returns (address deployment) {
        if (msg.sender != protocolFactory) {
            revert MockSovereignALMFactory__deploy_invalidDeployer();
        }

        SOTConstructorArgs memory args = abi.decode(_constructorArgs, (SOTConstructorArgs));
        deployment = address(new SOT{ salt: _salt }(args));
    }
}
