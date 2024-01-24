// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { SOTBase } from 'test/base/SOTBase.t.sol';

import {
    SovereignPool,
    SovereignPoolBase,
    SovereignPoolConstructorArgs,
    SovereignPoolSwapParams,
    SovereignPoolSwapContextData
} from 'valantis-core/test/base/SovereignPoolBase.t.sol';

import { SOTConstructorArgs } from 'src/structs/SOTStructs.sol';

contract SOTConcreteTest is SOTBase {
    function setUp() public virtual override {
        super.setUp();

        // Reserves in the ratio 1: 2000
        _setupBalanceForUser(address(this), address(token0), 10_000e18);
        _setupBalanceForUser(address(this), address(token1), 10_000e18);

        sot.depositLiquidity(5e18, 10_000e18, 0, 0);
    }

    function test_swap_amm() public {
        SovereignPoolSwapContextData memory data = SovereignPoolSwapContextData({
            externalContext: bytes(''),
            verifierContext: bytes(''),
            swapCallbackContext: bytes(''),
            swapFeeModuleContext: bytes('')
        });
        SovereignPoolSwapParams memory params = SovereignPoolSwapParams({
            isSwapCallback: false,
            isZeroToOne: true,
            amountIn: 1e18,
            amountOutMin: 0,
            recipient: address(this),
            deadline: block.timestamp + 2,
            swapTokenOut: address(token1),
            swapContext: data
        });
        pool.swap(params);
    }
}
