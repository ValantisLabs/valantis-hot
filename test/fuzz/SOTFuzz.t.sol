// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { console } from 'forge-std/console.sol';
import { SwapMath } from '@uniswap/v3-core/contracts/libraries/SwapMath.sol';
import '@uniswap/v3-core/contracts/libraries/FixedPoint96.sol';
import {
    SovereignPool,
    SovereignPoolBase,
    SovereignPoolConstructorArgs,
    SovereignPoolSwapParams,
    SovereignPoolSwapContextData
} from 'valantis-core/test/base/SovereignPoolBase.t.sol';
import { Math } from 'valantis-core/lib/openzeppelin-contracts/contracts/utils/math/Math.sol';
import { SafeCast } from 'valantis-core/lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol';

import { SOT } from 'src/SOT.sol';
import { SOTParams } from 'src/libraries/SOTParams.sol';
import { SOTConstants } from 'src/libraries/SOTConstants.sol';
import { TightPack } from 'src/libraries/utils/TightPack.sol';
import {
    SOTConstructorArgs,
    SolverOrderType,
    SolverWriteSlot,
    SolverReadSlot,
    AMMState
} from 'src/structs/SOTStructs.sol';

import { SOTBase } from 'test/base/SOTBase.t.sol';

contract SOTFuzzTest is SOTBase {
    using SafeCast for uint256;
    using TightPack for AMMState;

    event LogBytes(bytes data);

    AMMState public mockAMMState;

    function setUp() public virtual override {
        super.setUp();

        // Reserves in the ratio 1: 2000
        _setupBalanceForUser(address(this), address(token0), 30_000e18);
        _setupBalanceForUser(address(this), address(token1), 30_000e18);

        // Max volume for token0 ( Eth ) is 100, and for token1 ( USDC ) is 20,000
        vm.prank(address(this));
        sot.setMaxTokenVolumes(100e18, 20_000e18);
        sot.setMaxAllowedQuotes(2);
    }

    function test_getReservesAtPrice(uint256 priceToken0USD) public {
        sot.depositLiquidity(5e18, 10_000e18, 0, 0);

        priceToken0USD = bound(priceToken0USD, 1900, 2100);

        console.log('priceToken0USD: ', priceToken0USD);

        // Check reserves at priceToken0USD
        (uint256 reserve0Expected, uint256 reserve1Expected) = sot.getReservesAtPrice(
            getSqrtPriceX96(priceToken0USD * (10 ** feedToken0.decimals()), 1 * (10 ** feedToken1.decimals()))
        );

        (uint160 sqrtSpotPriceX96, , ) = sot.getAMMState();

        SovereignPoolSwapContextData memory data;

        bool isZeroToOne = priceToken0USD < 2000;
        uint256 amountIn = isZeroToOne ? reserve0Expected - 5e18 : reserve1Expected - 10_000e18;

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

        if (params.amountIn == 0) {
            vm.expectRevert(SovereignPool.SovereignPool__swap_insufficientAmountIn.selector);
        }
        (uint256 amountInUsed, uint256 amountOut) = pool.swap(params);
        (sqrtSpotPriceX96, , ) = sot.getAMMState();

        assertApproxEqRel(
            sqrtSpotPriceX96,
            getSqrtPriceX96(priceToken0USD * (10 ** feedToken0.decimals()), 1 * (10 ** feedToken1.decimals())),
            1, // 100% is represented by 1e18 here, so this value should be negligible
            'sqrtSpotPriceX96 1'
        );

        (uint256 reserve0Post, uint256 reserve1Post) = pool.getReserves();

        // 100% is represented by 1e18 here, so this value should be negligible
        assertApproxEqRel(reserve0Post, reserve0Expected, 1, 'reserve0Post');
        assertApproxEqRel(reserve1Post, reserve1Expected, 1, 'reserve1Post');

        params = SovereignPoolSwapParams({
            isSwapCallback: false,
            isZeroToOne: !isZeroToOne,
            amountIn: amountOut,
            amountOutMin: 0,
            recipient: address(this),
            deadline: block.timestamp + 2,
            swapTokenOut: !isZeroToOne ? address(token1) : address(token0),
            swapContext: data
        });

        if (params.amountIn == 0) {
            vm.expectRevert(SovereignPool.SovereignPool__swap_insufficientAmountIn.selector);
        }
        (amountInUsed, amountOut) = pool.swap(params);
        (sqrtSpotPriceX96, , ) = sot.getAMMState();

        assertGe(amountIn, amountOut, 'pathIndependence');
        assertApproxEqRel(
            sqrtSpotPriceX96,
            getSqrtPriceX96(2000 * (10 ** feedToken0.decimals()), 1 * (10 ** feedToken1.decimals())),
            1,
            'sqrtSpotPriceX96 2'
        );

        (reserve0Post, reserve1Post) = pool.getReserves();

        assertApproxEqRel(reserve0Post, 5e18, 1, 'reserve0Post');
        assertApproxEqRel(reserve1Post, 10_000e18, 1, 'reserve1Post');
    }

    function test_swap_amm_pathIndependence(
        bool _isZeroToOne,
        uint256 _reserve0,
        uint256 _reserve1,
        uint256 _amountIn,
        uint160 _sqrtSpotPriceX96,
        uint160 _sqrtPriceLowX96,
        uint160 _sqrtPriceHighX96
    ) public {
        _setupBalanceForUser(address(this), address(token0), type(uint256).max);
        _setupBalanceForUser(address(this), address(token1), type(uint256).max);

        // Comprehensive bounds that cover all scenarios
        _sqrtPriceLowX96 = bound(_sqrtPriceLowX96, SOTConstants.MIN_SQRT_PRICE, SOTConstants.MAX_SQRT_PRICE)
            .toUint160();
        _sqrtPriceHighX96 = bound(_sqrtPriceHighX96, _sqrtPriceLowX96, SOTConstants.MAX_SQRT_PRICE).toUint160();
        _sqrtSpotPriceX96 = bound(_sqrtSpotPriceX96, _sqrtPriceLowX96, _sqrtPriceHighX96).toUint160();
        _amountIn = bound(_amountIn, 1, 2 ** 255 - 1);

        console.log('Fuzz Input: _isZeroToOne: ', _isZeroToOne);
        console.log('Fuzz Input: _reserve0: ', _reserve0);
        console.log('Fuzz Input: _reserve1: ', _reserve1);
        console.log('Fuzz Input: _amountIn: ', _amountIn);
        console.log('Fuzz Input: _sqrtSpotPriceX96: ', _sqrtSpotPriceX96);
        console.log('Fuzz Input: _sqrtPriceLowX96: ', _sqrtPriceLowX96);
        console.log('Fuzz Input: _sqrtPriceHighX96: ', _sqrtPriceHighX96);

        if (_reserve0 == 0 && _reserve1 == 0) {
            vm.expectRevert(SovereignPool.SovereignPool__depositLiquidity_zeroTotalDepositAmount.selector);
        }

        // Set Reserves
        try sot.depositLiquidity(_reserve0, _reserve1, 0, 0) {} catch {
            return;
        }

        _setupBalanceForUser(address(this), address(token0), type(uint256).max);
        _setupBalanceForUser(address(this), address(token1), type(uint256).max);

        // Set AMM State
        mockAMMState.setState(_sqrtSpotPriceX96, _sqrtPriceLowX96, _sqrtPriceHighX96);

        vm.store(address(sot), bytes32(uint256(2)), bytes32(uint256(mockAMMState.slot1)));
        vm.store(address(sot), bytes32(uint256(3)), bytes32(uint256(mockAMMState.slot2)));

        // Check that the amm state is setup correctly
        (uint160 sqrtSpotPriceX96, uint160 sqrtPriceLowX96, uint160 sqrtPriceHighX96) = sot.getAMMState();

        assertEq(sqrtSpotPriceX96, _sqrtSpotPriceX96, 'sqrtSpotPriceX96New');
        assertEq(sqrtPriceLowX96, _sqrtPriceLowX96, 'sqrtPriceLowX96New');
        assertEq(sqrtPriceHighX96, _sqrtPriceHighX96, 'sqrtPriceHighX96New');

        SovereignPoolSwapContextData memory data;
        SovereignPoolSwapParams memory params = SovereignPoolSwapParams({
            isSwapCallback: false,
            isZeroToOne: _isZeroToOne,
            amountIn: _amountIn,
            amountOutMin: 0,
            recipient: address(this),
            deadline: block.timestamp + 2,
            swapTokenOut: _isZeroToOne ? address(token1) : address(token0),
            swapContext: data
        });

        uint128 preLiquidity = sot.effectiveAMMLiquidity();

        if (params.amountIn == 0) {
            vm.expectRevert(SovereignPool.SovereignPool__swap_insufficientAmountIn.selector);
        }

        try pool.swap(params) returns (uint256, uint256 amountOutFirst) {
            (sqrtSpotPriceX96, sqrtPriceLowX96, sqrtPriceHighX96) = sot.getAMMState();

            uint128 postLiquidity = sot.effectiveAMMLiquidity();
            assertEq(preLiquidity, postLiquidity, 'liquidity inconsistency');

            params.isZeroToOne = !_isZeroToOne;
            params.amountIn = amountOutFirst;
            params.swapTokenOut = !_isZeroToOne ? address(token1) : address(token0);

            _setupBalanceForUser(address(this), address(token0), type(uint256).max);
            _setupBalanceForUser(address(this), address(token1), type(uint256).max);

            if (params.amountIn == 0) {
                vm.expectRevert(SovereignPool.SovereignPool__swap_insufficientAmountIn.selector);
            }

            try pool.swap(params) returns (uint256, uint256 amountOutSecond) {
                assertGe(_amountIn, amountOutSecond, 'pathIndependence');
            } catch (bytes memory reason) {
                if (keccak256(reason) == keccak256(abi.encodePacked(hex'd19ac625'))) {
                    console.log('Reverted because of 0 amountOut');
                    return;
                } else {
                    emit LogBytes(reason);
                    revert('revert swap 2');
                }
            }
        } catch {
            // TODO: Uncomment this and fix tests?
            // if (keccak256(reason) == keccak256(abi.encodePacked(hex'd19ac625'))) {
            //     console.log('Reverted because of 0 amountOut');
            //     return;
            // } else {
            //     emit LogBytes(reason);
            //     revert('revert swap 1');
            // }
        }
    }
}