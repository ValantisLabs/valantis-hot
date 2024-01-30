// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { SOT } from 'src/SOT.sol';
import { SOTConstructorArgs } from 'src/structs/SOTStructs.sol';

library SOTFactoryLibAddress {
    /************************************************
     *  FUNCTIONS
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
}
