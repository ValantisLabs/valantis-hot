// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { HOTConstructorArgs } from '../../src/structs/HOTStructs.sol';
import { HOT } from '../../src/HOT.sol';

contract HOTDeployer {
    function deployHOT(HOTConstructorArgs memory _hotArgs) public returns (HOT hot) {
        hot = new HOT(_hotArgs);
    }
}
