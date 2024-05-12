// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { console } from 'forge-std/console.sol';

import { SwapMath } from '../../lib/v3-core/contracts/libraries/SwapMath.sol';
import '../../lib/v3-core/contracts/libraries/FixedPoint96.sol';
import { Math } from '../../lib/valantis-core/lib/openzeppelin-contracts/contracts/utils/math/Math.sol';
import { SafeCast } from '../../lib/valantis-core/lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol';
import {
    SovereignPool,
    SovereignPoolBase,
    SovereignPoolConstructorArgs,
    SovereignPoolSwapParams,
    SovereignPoolSwapContextData
} from '../../lib/valantis-core/test/base/SovereignPoolBase.t.sol';
import { SwapFeeModuleData } from '../../lib/valantis-core/src/swap-fee-modules/interfaces/ISwapFeeModule.sol';

import { HOT, ALMLiquidityQuoteInput } from '../../src/HOT.sol';
import { HOTParams } from '../../src/libraries/HOTParams.sol';
import { HOTOracle } from '../../src/HOTOracle.sol';
import { HOTConstructorArgs, HybridOrderType, HotWriteSlot, HotReadSlot } from '../../src/structs/HOTStructs.sol';
import { HOTConstants } from '../../src/libraries/HOTConstants.sol';
import { TightPack } from '../../src/libraries/utils/TightPack.sol';

import { HOTBase } from '../base/HOTBase.t.sol';

contract HOTFuzzTest is HOTBase {
    using SafeCast for uint256;

    event LogBytes(bytes data);

    function setUp() public virtual override {
        super.setUp();

        // Reserves in the ratio 1: 2000
        _setupBalanceForUser(address(this), address(token0), 30_000e18);
        _setupBalanceForUser(address(this), address(token1), 30_000e18);

        // Max volume for token0 ( Eth ) is 100, and for token1 ( USDC ) is 20,000
        vm.prank(address(this));
        hot.setMaxTokenVolumes(100e18, 20_000e18);
        hot.setMaxAllowedQuotes(2);
    }

    function test_getReservesAtPrice(uint256 priceToken0USD) public {
        hot.depositLiquidity(5e18, 10_000e18, 0, 0);

        priceToken0USD = bound(priceToken0USD, 1900, 2100);

        console.log('priceToken0USD: ', priceToken0USD);

        // Check reserves at priceToken0USD
        (uint256 reserve0Expected, uint256 reserve1Expected) = hot.getReservesAtPrice(
            getSqrtPriceX96(priceToken0USD * (10 ** feedToken0.decimals()), 1 * (10 ** feedToken1.decimals()))
        );

        (uint160 sqrtSpotPriceX96, , ) = hot.getAMMState();

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
        (sqrtSpotPriceX96, , ) = hot.getAMMState();

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
        (sqrtSpotPriceX96, , ) = hot.getAMMState();

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
        _sqrtPriceLowX96 = bound(_sqrtPriceLowX96, HOTConstants.MIN_SQRT_PRICE, HOTConstants.MAX_SQRT_PRICE)
            .toUint160();
        _sqrtPriceHighX96 = bound(_sqrtPriceHighX96, _sqrtPriceLowX96, HOTConstants.MAX_SQRT_PRICE).toUint160();
        _sqrtSpotPriceX96 = bound(_sqrtSpotPriceX96, _sqrtPriceLowX96, _sqrtPriceHighX96).toUint160();
        _amountIn = bound(_amountIn, 1, 2 ** 255 - 1);

        console.log('Fuzz Input: _isZeroToOne: ', _isZeroToOne);
        console.log('Fuzz Input: _reserve0: ', _reserve0);
        console.log('Fuzz Input: _reserve1: ', _reserve1);
        console.log('Fuzz Input: _amountIn: ', _amountIn);
        console.log('Fuzz Input: _sqrtSpotPriceX96: ', _sqrtSpotPriceX96);
        console.log('Fuzz Input: _sqrtPriceLowX96: ', _sqrtPriceLowX96);
        console.log('Fuzz Input: _sqrtPriceHighX96: ', _sqrtPriceHighX96);

        // Set AMM State
        _setAMMState(_sqrtSpotPriceX96, _sqrtPriceLowX96, _sqrtPriceHighX96);

        if (_reserve0 == 0 && _reserve1 == 0) {
            vm.expectRevert(SovereignPool.SovereignPool__depositLiquidity_zeroTotalDepositAmount.selector);
        }

        // Set Reserves
        try hot.depositLiquidity(_reserve0, _reserve1, 0, 0) {} catch {
            return;
        }

        _setupBalanceForUser(address(this), address(token0), type(uint256).max);
        _setupBalanceForUser(address(this), address(token1), type(uint256).max);

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

        uint128 preLiquidity = hot.effectiveAMMLiquidity();

        if (params.amountIn == 0) {
            vm.expectRevert(SovereignPool.SovereignPool__swap_insufficientAmountIn.selector);
        }

        try pool.swap(params) returns (uint256, uint256 amountOutFirst) {
            uint128 postLiquidity = hot.effectiveAMMLiquidity();
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
        } catch {}
    }
}
