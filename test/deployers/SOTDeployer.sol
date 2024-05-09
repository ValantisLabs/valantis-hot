// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { SOTConstructorArgs } from '../../src/structs/SOTStructs.sol';
import { SOT } from '../../src/SOT.sol';

contract SOTDeployer {
    function deploySOT(SOTConstructorArgs memory _sotArgs) public returns (SOT sot) {
        sot = new SOT(_sotArgs);
    }
}
