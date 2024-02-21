// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { Math } from 'valantis-core/lib/openzeppelin-contracts/contracts/utils/math/Math.sol';

contract MathHelper {
    function mulDiv(uint256 x, uint256 y, uint256 z) public pure returns (uint256) {
        return Math.mulDiv(x, y, z);
    }
}
