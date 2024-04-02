// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { Strings } from 'valantis-core/lib/openzeppelin-contracts/contracts/utils/Strings.sol';

library DeployHelper {
    function getPath() internal view returns (string memory) {
        return string.concat(string.concat(string('./deployments/'), Strings.toString(block.chainid)), '.json');
    }
}
