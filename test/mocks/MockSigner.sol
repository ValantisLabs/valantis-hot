// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { HybridOrderType } from '../../src/structs/HOTStructs.sol';

contract MockSigner {
    /**
     * @dev EIP-1271 magic value
     * bytes4(keccak256("isValidSignature(bytes32,bytes)")
     */
    bytes4 internal constant MAGICVALUE = 0x1626ba7e;

    function getSignedQuote(HybridOrderType memory hot) public pure returns (bytes memory signedQuoteExternalContext) {
        bytes memory signature;

        signedQuoteExternalContext = abi.encode(hot, signature);
    }

    /**
        @dev EIP 1271 compliant smart contract signer
        @dev Accepts all signature verification requests for now.
     */
    function isValidSignature(bytes32, bytes memory) public pure returns (bytes4 magicValue) {
        return MAGICVALUE;
    }
}
