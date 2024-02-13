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

import { SOTConstructorArgs, SolverOrderType, SolverWriteSlot } from 'src/structs/SOTStructs.sol';

import { SOTSigner } from 'test/helpers/SOTSigner.sol';

contract SOTConcreteTest is SOTBase {
    function setUp() public virtual override {
        super.setUp();

        // Reserves in the ratio 1: 2000
        _setupBalanceForUser(address(this), address(token0), 30_000e18);
        _setupBalanceForUser(address(this), address(token1), 30_000e18);

        sot.depositLiquidity(5e18, 10_000e18, 0, 0);

        // Max volume for token0 ( Eth ) is 100, and for token1 ( USDC ) is 20,000
        vm.prank(address(this));
        sot.setMaxTokenVolumes(100e18, 20_000e18);
    }

    function test_swap_amm() public {
        PoolState memory preState = getPoolState();

        SovereignPoolSwapContextData memory data;
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

        uint256 preGas = gasleft();

        pool.swap(params);
        uint256 postGas = gasleft();
        console.log('gas: ', preGas - postGas);

        PoolState memory postState = getPoolState();

        assertEq(postState.reserve0, preState.reserve0 + 1e18, 'reserve0');
        // TODO: Math to check if this is the correct value?
        // TODO: Use check pool state here
        // assertEq(postState.reserve1, preState.reserve1 - 1e18 * 2000, 'reserve1');
    }

    // TODO: Check why 6 reserves of amount1 are left in the pool
    function test_swap_amm_depleteLiquidityInOneToken() public {
        SovereignPoolSwapContextData memory data;
        SovereignPoolSwapParams memory params = SovereignPoolSwapParams({
            isSwapCallback: false,
            isZeroToOne: true,
            amountIn: 1e28, // Swap large amount to deplete 1 token
            amountOutMin: 0,
            recipient: address(this),
            deadline: block.timestamp + 2,
            swapTokenOut: address(token1),
            swapContext: data
        });

        // Deplete liquidity in one token
        (uint256 amountInUsed, uint256 amountOut) = pool.swap(params);

        PoolState memory postState = getPoolState();

        console.log('amountInUsed 1: ', amountInUsed);
        console.log('amountOut 1: ', amountOut);
        console.log('reserve0: ', postState.reserve0);
        console.log('reserve1: ', postState.reserve1);
        console.log('sqrtSpotPriceX96: ', postState.sqrtSpotPriceX96);
        console.log('sqrtPriceLowX96: ', postState.sqrtPriceLowX96);
        console.log('sqrtPriceHighX96: ', postState.sqrtPriceHighX96);

        params.amountIn = 1e18;

        (amountInUsed, amountOut) = pool.swap(params);

        assertEq(amountInUsed, 0, 'amountInUsed Wrong Direction');
        assertEq(amountOut, 0, 'amountOut Wrong Direction');

        params.isZeroToOne = false;
        params.swapTokenOut = address(token0);

        // It should be possible to make another swap in the reverse direction
        (amountInUsed, amountOut) = pool.swap(params);

        assertNotEq(amountInUsed, 0, 'amountInUsed Right Direction');
        assertNotEq(amountOut, 0, 'amountOut Right Direction');
    }

    function test_swap_solver_contractSigner() public {
        // Test Swap with Contract Signer
        SovereignPoolSwapContextData memory data = SovereignPoolSwapContextData({
            externalContext: mockSigner.getSignedQuote(_getSensibleSOTParams()),
            verifierContext: bytes(''),
            swapCallbackContext: bytes(''),
            swapFeeModuleContext: bytes('1')
        });

        PoolState memory preState = getPoolState();

        SovereignPoolSwapParams memory params = SovereignPoolSwapParams({
            isSwapCallback: false,
            isZeroToOne: true,
            amountIn: 1e18,
            amountOutMin: 0,
            recipient: makeAddr('RECIPIENT'),
            deadline: block.timestamp + 2,
            swapTokenOut: address(token1),
            swapContext: data
        });

        pool.swap(params);
        PoolState memory postState = getPoolState();

        PoolState memory expectedState = PoolState({
            reserve0: preState.reserve0 + 1e18,
            reserve1: preState.reserve1 - 1e18 * 1980,
            sqrtSpotPriceX96: getSqrtPriceX96(2005 * (10 ** feedToken0.decimals()), 1 * (10 ** feedToken1.decimals())),
            sqrtPriceLowX96: preState.sqrtPriceLowX96,
            sqrtPriceHighX96: preState.sqrtPriceHighX96,
            managerFee0: 0,
            managerFee1: 0
        });

        checkPoolState(expectedState, postState);
    }

    function test_swap_solver_EOASigner() public {
        sot.setSigner(EOASigner);

        // Test Swap with EOA Signer
        SovereignPoolSwapContextData memory data = SovereignPoolSwapContextData({
            externalContext: getEOASignedQuote(_getSensibleSOTParams(), EOASignerPrivateKey),
            verifierContext: bytes(''),
            swapCallbackContext: bytes(''),
            swapFeeModuleContext: bytes('1')
        });

        SovereignPoolSwapParams memory params = SovereignPoolSwapParams({
            isSwapCallback: false,
            isZeroToOne: true,
            amountIn: 1e18,
            amountOutMin: 0,
            recipient: makeAddr('RECIPIENT'),
            deadline: block.timestamp + 2,
            swapTokenOut: address(token1),
            swapContext: data
        });

        uint256 gasUsed = gasleft();
        pool.swap(params);
        gasUsed = gasUsed - gasleft();
        console.log('gas: ', gasUsed);
    }

    function test_swap_solver_invalidSignature() public {
        sot.setSigner(vm.addr(0x111));

        // Test Swap with EOA Signer
        SovereignPoolSwapContextData memory data = SovereignPoolSwapContextData({
            externalContext: getEOASignedQuote(_getSensibleSOTParams(), EOASignerPrivateKey),
            verifierContext: bytes(''),
            swapCallbackContext: bytes(''),
            swapFeeModuleContext: bytes('1')
        });

        SovereignPoolSwapParams memory params = SovereignPoolSwapParams({
            isSwapCallback: false,
            isZeroToOne: true,
            amountIn: 1e18,
            amountOutMin: 0,
            recipient: makeAddr('RECIPIENT'),
            deadline: block.timestamp + 2,
            swapTokenOut: address(token1),
            swapContext: data
        });

        vm.expectRevert(SOT.SOT__getLiquidityQuote_invalidSignature.selector);
        pool.swap(params);
    }

    function test_swap_solver_replayProtection() public {
        sot.setSigner(EOASigner);

        SovereignPoolSwapContextData memory data = SovereignPoolSwapContextData({
            externalContext: getEOASignedQuote(_getSensibleSOTParams(), EOASignerPrivateKey),
            verifierContext: bytes(''),
            swapCallbackContext: bytes(''),
            swapFeeModuleContext: bytes('1')
        });

        SovereignPoolSwapParams memory params = SovereignPoolSwapParams({
            isSwapCallback: false,
            isZeroToOne: true,
            amountIn: 1e18,
            amountOutMin: 0,
            recipient: makeAddr('RECIPIENT'),
            deadline: block.timestamp + 2,
            swapTokenOut: address(token1),
            swapContext: data
        });

        pool.swap(params);

        vm.expectRevert(SOTParams.SOTParams__validateBasicParams_replayedQuote.selector);

        pool.swap(params);
    }

    function test_singleSidedLiquidity() public {
        sot.withdrawLiquidity(5e18, 10_000e18, address(this), 0, 0);

        (uint256 amount0, uint256 amount1) = pool.getReserves();
        assertEq(amount0 + amount1, 0, 'pool not empty');

        // Depositing single sided liquidity
        sot.depositLiquidity(5e18, 0, 0, 0);

        (amount0, amount1) = pool.getReserves();

        assertEq(amount0, 5e18, 'amount0');
        assertEq(amount1, 0, 'amount1');

        SolverOrderType memory sotParams = _getSensibleSOTParams();

        (, uint160 sqrtSpotPriceLowX96, ) = sot.getAmmState();
        sotParams.sqrtSpotPriceX96New = sqrtSpotPriceLowX96;

        // Update the Oracle so that it allows the spot price to be updated to the edge
        feedToken0.updateAnswer(1500e8);
        sotParams.solverPriceX192Discounted = 1500 << 192;

        // Set Spot price to priceLow with empty SOT
        SovereignPoolSwapContextData memory data = SovereignPoolSwapContextData({
            externalContext: mockSigner.getSignedQuote(sotParams),
            verifierContext: bytes(''),
            swapCallbackContext: bytes(''),
            swapFeeModuleContext: bytes('1')
        });

        // AmountIn is set to 1, so that SovereignPool doesn't revert
        SovereignPoolSwapParams memory params = SovereignPoolSwapParams({
            isSwapCallback: false,
            isZeroToOne: false,
            amountIn: 1,
            amountOutMin: 0,
            recipient: makeAddr('RECIPIENT'),
            deadline: block.timestamp + 2,
            swapTokenOut: address(token0),
            swapContext: data
        });

        // Perform SOT swap to update the spot price
        pool.swap(params);

        (amount0, amount1) = pool.getReserves();

        // Assert that amount1 reserves are empty
        assertEq(amount0, 5e18, 'amount0');
        assertEq(amount1, 0, 'amount1');

        data.swapFeeModuleContext = bytes('');
        data.externalContext = bytes('');

        params.amountIn = 1e18;
        params.swapContext = data;

        (uint256 amountInUsed, uint256 amountOut) = pool.swap(params);

        assertNotEq(amountInUsed, 0, 'amountInUsed Right Direction');
        assertNotEq(amountOut, 0, 'amountOut Right Direction');
    }

    function test_swap_solver_baseSolver() public {
        sot.setSigner(EOASigner);

        // Test Swap with EOA Signer
        SovereignPoolSwapContextData memory data = SovereignPoolSwapContextData({
            externalContext: getEOASignedQuote(_getSensibleSOTParams(), EOASignerPrivateKey),
            verifierContext: bytes(''),
            swapCallbackContext: bytes(''),
            swapFeeModuleContext: bytes('1')
        });

        SovereignPoolSwapParams memory params = SovereignPoolSwapParams({
            isSwapCallback: false,
            isZeroToOne: true,
            amountIn: 1e18,
            amountOutMin: 0,
            recipient: makeAddr('RECIPIENT'),
            deadline: block.timestamp + 2,
            swapTokenOut: address(token1),
            swapContext: data
        });

        pool.swap(params);

        SolverOrderType memory sotParams = _getSensibleSOTParams();
        sotParams.expectedFlag = 1;
        sotParams.sqrtSpotPriceX96New = getSqrtPriceX96(
            2010 * (10 ** feedToken0.decimals()),
            1 * (10 ** feedToken1.decimals())
        );

        PoolState memory preState = getPoolState();

        params.swapContext.externalContext = getEOASignedQuote(sotParams, EOASignerPrivateKey);

        pool.swap(params);

        PoolState memory postState = getPoolState();

        // Check that the spot price did not get updated to the new value
        PoolState memory expectedState = PoolState({
            reserve0: preState.reserve0 + 1e18,
            reserve1: preState.reserve1 - 1e18 * 2000,
            sqrtSpotPriceX96: getSqrtPriceX96(2005 * (10 ** feedToken0.decimals()), 1 * (10 ** feedToken1.decimals())),
            sqrtPriceLowX96: preState.sqrtPriceLowX96,
            sqrtPriceHighX96: preState.sqrtPriceHighX96,
            managerFee0: 0,
            managerFee1: 0
        });

        checkPoolState(expectedState, postState);
        // checkSolverWriteSlot(preSolverWriteSlot, sot.solverWriteSlot());
    }

    function test_getReservesAtPrice() public /** uint256 priceToken0USD */ {
        // uint256 priceToken0USD = bound(priceToken0USD, 1900, 2100);
        uint256 priceToken0USD = 2050;
        // uint160 sqrtPriceX96 = 3498620926022713237135550346861;
        // 3498620926022713023499608260608;

        (uint256 reserve0Pre, uint256 reserve1Pre) = sot.getReservesAtPrice(
            getSqrtPriceX96(2000 * (10 ** feedToken0.decimals()), 1 * (10 ** feedToken1.decimals()))
        );

        assertEq(reserve0Pre, 5e18, 'reserve0Pre');
        assertEq(reserve1Pre, 10_000e18, 'reserve1Pre');

        // Check reserves at priceToken0USD
        (uint256 reserve0Expected, uint256 reserve1Expected) = sot.getReservesAtPrice(
            getSqrtPriceX96(priceToken0USD * (10 ** feedToken0.decimals()), 1 * (10 ** feedToken1.decimals()))
        );

        // (uint256 reserve0Expected, uint256 reserve1Expected) = sot.getReservesAtPrice(sqrtPriceX96);

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

    function test_pause() public {
        // Default SOT is unpaused
        assertFalse(sot.isPaused(), 'isPaused error 1');

        // Set to the same value again
        sot.setPause(false);
        assertFalse(sot.isPaused(), 'isPaused error 2');

        // Pause the SOT. At this point SOT has (5e18, 10_000e18) liquidity
        sot.setPause(true);
        assertTrue(sot.isPaused(), 'isPaused error 3');

        // Deposits are paused
        vm.expectRevert(SOT.SOT__onlyUnpaused.selector);
        sot.depositLiquidity(1e18, 1e18, 0, 0);

        // Swaps are paused
        SovereignPoolSwapContextData memory data;
        vm.expectRevert(SOT.SOT__onlyUnpaused.selector);
        SovereignPoolSwapParams memory params = SovereignPoolSwapParams({
            isSwapCallback: false,
            isZeroToOne: false,
            amountIn: 1e8,
            amountOutMin: 0,
            recipient: address(this),
            deadline: block.timestamp + 2,
            swapTokenOut: address(token0),
            swapContext: data
        });
        pool.swap(params);

        // Withdrawals are never paused.
        (uint256 reserve0, uint256 reserve1) = pool.getReserves();
        uint256 preBalance0 = token0.balanceOf(address(this));
        uint256 preBalance1 = token1.balanceOf(address(this));

        sot.withdrawLiquidity(5e18, 10_000e18, address(this), 0, 0);

        (reserve0, reserve1) = pool.getReserves();
        assertEq(reserve0, 0, 'reserve0 1');
        assertEq(reserve1, 0, 'reserve1 1');
        assertEq(token0.balanceOf(address(this)) - preBalance0, 5e18, 'balance0');
        assertEq(token1.balanceOf(address(this)) - preBalance1, 10_000e18, 'balance1');

        // Unpause the SOT
        sot.setPause(false);
        assertFalse(sot.isPaused(), 'isPaused error 4');

        // Deposits are unpaused
        sot.depositLiquidity(1e18, 1e18, 0, 0);
        (reserve0, reserve1) = pool.getReserves();
        assertEq(reserve0, 1e18, 'reserve0 2');
        assertEq(reserve1, 1e18, 'reserve1 2');
    }

    function test_spotPriceRange() public {}
}

/**
    Test Cases:

    ==> Solver Swap 
        * [ ] All types of signatures, failure and edge cases
        * [ ] Multiple quotes in the same block 
            - [*] Discounted/Non-Discounted
            - [ ] Valid/Invalid
            - [*] Replay Protection
            - [ ] Effects on liquidity
        * [ ] AMM Spot Price Updates
            - [ ] Frontrun attacks
            - [*] Solver swap combined with AMM swap
            - [ ] Pool Liquidity should be calculated correctly after update
        * [ ] Reentrancy Protection
        * [ ] Interactions with Oracle
            - [ ] High deviation should revert
        * [*] Valid/Invalid fee paths
        * [ ] Effects on amm fee
        * [ ] Calculation of Manager Fee
        * [*] Correct amountIn and out calculations 
        * [ ] Solver fee in BIPS is applied correctly

    ==> AMM Swap
        * [*] Effects on AMM when very large swaps drain pool in one token, spot price etc.
        * [*] Valid/Invalid fee paths
        * [ ] AMM Math is as expected
        * [ ] Liquidity is calculated correctly
        * [ ] Set price bounds shifts liquidity correctly
        * [ ] Fee growth is correct, pool is soft locked before solver swap
        * [ ] No AMM swap is every able to change Solver Write Slot
        * [*] Single Sided Liquidity
    
    ==> General Ops
        * [*] Pause/Unpause works as expected [done]
        * [ ] Constructor sets all values correctly
        * [ ] Get Reserves at Price function is correct
        * [ ] All important functions are reentrancy protected
        * [ ] Manager is able to withdraw fee from Sovereign Pool
        * [ ] Critical Manager operations are timelocked
        * [ ] Check spot price manipulation on deposit
    
    ==> Gas
        * [ ] Prepare setup for correct gas reports
        * [ ] Solvers should do maximum 2 storage writes in SOT

    ==> Imp
        * [ ] Fuzz at edges of liquidity to make sure there are no path independence issues
        * [ ] Write tests for LiquidityAmounts library especially at edges
*/
