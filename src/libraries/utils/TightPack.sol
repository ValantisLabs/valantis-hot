// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

/**
    @notice Helper library for tight packing multiplke uint160 values into minimum amount of uint256 slots.
 */
library TightPack {
    struct PackedState {
        uint256 slot1;
        uint256 slot2;
    }

    /**
        @notice Packs 3 uint160 values into 2 uint256 slots.
        @param a uint160 value to pack into slot1.
        @param b uint160 value to pack into slot1 and slot2.
        @param c uint160 value to pack into slot2.
        @return state PackedState struct containing slot1 and slot2.
        @dev slot1: << 32 empty bits | upper 64 bits of b | all 160 bits of a >>
             slot2: << lower 96 bits of b | all 160 bits of c >>
     */
    function packState(uint160 a, uint160 b, uint160 c) internal pure returns (PackedState memory state) {
        uint256 slot1;
        uint256 slot2;
        assembly {
            slot1 := or(shl(160, shr(96, b)), a)
            slot2 := or(shl(160, b), c)
        }

        state.slot1 = slot1;
        state.slot2 = slot2;
    }

    /**
        @notice Unpacks 2 uint256 slots into 3 uint160 values.
        @param state PackedState struct containing slot1 and slot2.
        @return a uint160 value unpacked from slot1.
        @return b uint160 value unpacked from slot1 and slot2.
        @return c uint160 value unpacked from slot2.
        @dev slot1: << 32 empty bits | upper 64 bits of b | all 160 bits of a >>
             slot2: << lower 96 bits of b | all 160 bits of c >>
     */
    function unpackState(PackedState storage state) internal view returns (uint160 a, uint160 b, uint160 c) {
        uint256 slot1 = state.slot1;
        uint256 slot2 = state.slot2;

        assembly {
            a := shr(96, shl(96, slot1))
            c := shr(96, shl(96, slot2))
            b := or(shl(96, shr(160, slot1)), shr(160, slot2))
        }
    }

    function getA(PackedState storage state) internal view returns (uint160 a) {
        uint256 slot1 = state.slot1;
        assembly {
            a := shr(96, shl(96, slot1))
        }
    }

    function getB(PackedState storage state) internal view returns (uint160 b) {
        uint256 slot1 = state.slot1;
        uint256 slot2 = state.slot2;
        assembly {
            b := or(shl(96, shr(160, slot1)), shr(160, slot2))
        }
    }

    function getC(PackedState storage state) internal view returns (uint160 c) {
        uint256 slot2 = state.slot2;
        assembly {
            c := shr(96, shl(96, slot2))
        }
    }

    function setA(PackedState storage state, uint160 a) internal {
        uint256 slot1 = state.slot1;
        assembly {
            slot1 := or(shl(160, shr(160, slot1)), a)
        }
        state.slot1 = slot1;
    }

    function setB(PackedState storage state, uint160 b) internal {
        (uint160 oldA, , uint160 oldC) = unpackState(state);
        PackedState memory tempState = packState(oldA, b, oldC);
        state.slot1 = tempState.slot1;
        state.slot2 = tempState.slot2;
    }

    function setC(PackedState storage state, uint160 c) internal {
        uint256 slot2 = state.slot2;
        assembly {
            slot2 := or(shl(160, shr(160, slot2)), c)
        }
        state.slot2 = slot2;
    }

    function setState(PackedState storage state, uint160 a, uint160 b, uint160 c) internal {
        PackedState memory tempState = packState(a, b, c);
        state.slot1 = tempState.slot1;
        state.slot2 = tempState.slot2;
    }
}
