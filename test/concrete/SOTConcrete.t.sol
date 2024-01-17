// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { SOTBase } from 'test/base/SOTBase.t.sol';

import { SovereignPoolSwapContextData } from 'valantis-core/src/pools/structs/SovereignPoolStructs.sol';
import {
    SovereignPool,
    SovereignPoolBase,
    SovereignPoolConstructorArgs,
    SovereignPoolSwapParams
} from 'valantis-core/test/base/SovereignPoolBase.t.sol';

import { SOTConstructorArgs } from 'src/structs/SOTStructs.sol';

contract SOTConcreteTest is SOTBase {
    function test_swap_solver() public {
        // SovereignPoolSwapContextData memory data = SovereignPoolSwapContextData({
        //     externalContext: bytes(''),
        //     verifierContext: bytes(''),
        //     swapCallbackContext: bytes(''),
        //     swapFeeModuleContext: bytes('')
        // });
        // SovereignPoolSwapParams memory params = SovereignPoolSwapParams({
        //     isSwapCallback: false,
        //     isZeroToOne: true,
        //     amountIn: 1e18,
        //     amountOutMin: 0,
        //     recipient: address(this),
        //     swapTokenOut: address(this),
        //     swapContext: data
        // });
        // pool.swap(params);
    }
}
