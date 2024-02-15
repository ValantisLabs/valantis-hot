// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { console } from 'forge-std/console.sol';

import { SOT } from 'src/SOT.sol';
import { SOTParams } from 'src/libraries/SOTParams.sol';

import { SOTBase } from 'test/base/SOTBase.t.sol';

import {
    SovereignPool,
    SovereignPoolBase,
    SovereignPoolConstructorArgs,
    SovereignPoolSwapParams,
    SovereignPoolSwapContextData
} from 'valantis-core/test/base/SovereignPoolBase.t.sol';

import { SOTConstructorArgs, SolverOrderType, SolverWriteSlot, SolverReadSlot } from 'src/structs/SOTStructs.sol';

import { SOTSigner } from 'test/helpers/SOTSigner.sol';

import { Math } from 'valantis-core/lib/openzeppelin-contracts/contracts/utils/math/Math.sol';
import { SafeCast } from 'valantis-core/lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol';

contract SOTFuzzTest is SOTBase {
    using SafeCast for uint256;

    function setUp() public virtual override {
        super.setUp();

        // Reserves in the ratio 1: 2000
        _setupBalanceForUser(address(this), address(token0), 30_000e18);
        _setupBalanceForUser(address(this), address(token1), 30_000e18);

        sot.depositLiquidity(5e18, 10_000e18, 0, 0);

        // Max volume for token0 ( Eth ) is 100, and for token1 ( USDC ) is 20,000
        vm.prank(address(this));
        sot.setMaxTokenVolumes(100e18, 20_000e18);
        sot.setMaxAllowedQuotes(2);
    }

    function test_getReservesAtPrice(uint256 priceToken0USD) public {
        // uint256 priceToken0USD = bound(priceToken0USD, 1900, 2100);
        priceToken0USD = 2050;

        (uint256 reserve0Pre, uint256 reserve1Pre) = sot.getReservesAtPrice(
            getSqrtPriceX96(2000 * (10 ** feedToken0.decimals()), 1 * (10 ** feedToken1.decimals()))
        );

        assertEq(reserve0Pre, 5e18, 'reserve0Pre');
        assertEq(reserve1Pre, 10_000e18, 'reserve1Pre');

        // Check reserves at priceToken0USD
        (uint256 reserve0Expected, uint256 reserve1Expected) = sot.getReservesAtPrice(
            getSqrtPriceX96(priceToken0USD * (10 ** feedToken0.decimals()), 1 * (10 ** feedToken1.decimals()))
        );

        console.log(
            'spotPrice for reserves: ',
            getSqrtPriceX96(priceToken0USD * (10 ** feedToken0.decimals()), 1 * (10 ** feedToken1.decimals()))
        );

        SovereignPoolSwapContextData memory data;

        bool isZeroToOne = priceToken0USD < 2000;
        uint256 amountIn = isZeroToOne ? reserve0Expected - reserve0Pre : reserve1Expected - reserve1Pre;

        SovereignPoolSwapParams memory params = SovereignPoolSwapParams({
            isSwapCallback: false,
            isZeroToOne: isZeroToOne,
            amountIn: amountIn,
            amountOutMin: 0,
            recipient: address(this),
            deadline: block.timestamp + 2,
            swapTokenOut: isZeroToOne ? address(token1) : address(token0),
            swapContext: data
        });
        pool.swap(params);

        (uint256 reserve0Post, uint256 reserve1Post) = pool.getReserves();

        assertApproxEqAbs(reserve0Post, reserve0Expected, 1, 'reserve0Post');
        assertApproxEqAbs(reserve1Post, reserve1Expected, 1, 'reserve1Post');

        console.log('reserve0Pre: ', reserve0Pre);
        console.log('reserve1Pre: ', reserve1Pre);
        console.log('reserve0Expected: ', reserve0Expected);
        console.log('reserve1Expected: ', reserve1Expected);
        console.log('reserve0Post: ', reserve0Post);
        console.log('reserve1Post: ', reserve1Post);
    }
}
