// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

library TightPack {
    function packSlots(uint160 a, uint160 b, uint160 c) internal pure returns (uint256 slot1, uint256 slot2) {
        assembly {
            slot1 := or(shl(160, b), a)
            slot2 := or(shl(160, b), c)
        }
    }

    function unpackSlots(uint256 slot1, uint256 slot2) internal pure returns (uint160 a, uint160 b, uint160 c) {
        assembly {
            a := shr(96, shl(96, slot1))
            c := shr(96, shl(96, slot2))
            b := or(shr(160, slot1), shl(80, shr(160, slot2)))
        }
    }
}

//  lower 80 bytes of b | a
//  higher 80 bytes of b | c
