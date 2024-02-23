// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { console } from 'forge-std/console.sol';
import { SwapMath } from '@uniswap/v3-core/contracts/libraries/SwapMath.sol';
import '@uniswap/v3-core/contracts/libraries/FixedPoint96.sol';
import { Math } from 'valantis-core/lib/openzeppelin-contracts/contracts/utils/math/Math.sol';
import { SafeCast } from 'valantis-core/lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol';
import {
    SovereignPool,
    SovereignPoolBase,
    SovereignPoolConstructorArgs,
    SovereignPoolSwapParams,
    SovereignPoolSwapContextData
} from 'valantis-core/test/base/SovereignPoolBase.t.sol';

import { SOT } from 'src/SOT.sol';
import { SOTParams } from 'src/libraries/SOTParams.sol';
import { SOTConstructorArgs, SolverOrderType, SolverWriteSlot, SolverReadSlot } from 'src/structs/SOTStructs.sol';

import { SOTBase } from 'test/base/SOTBase.t.sol';


contract SOTConcreteTest is SOTBase {
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
            amountIn: 1e30, // Swap large amount to deplete 1 token
            amountOutMin: 0,
            recipient: address(this),
            deadline: block.timestamp + 2,
            swapTokenOut: address(token1),
            swapContext: data
        });

        // Deplete liquidity in one token
        (uint256 amountInUsed, uint256 amountOut) = pool.swap(params);

        PoolState memory postState = getPoolState();

        // Check that sqrt spot price matches the left-most bound
        assertEq(postState.sqrtSpotPriceX96, postState.sqrtPriceLowX96, 'Wrong sqrt spot price update');

        console.log('amountInUsed 1: ', amountInUsed);
        console.log('amountOut 1: ', amountOut);
        console.log('reserve0: ', postState.reserve0);
        console.log('reserve1: ', postState.reserve1);
        console.log('sqrtSpotPriceX96: ', postState.sqrtSpotPriceX96);
        console.log('sqrtPriceLowX96: ', postState.sqrtPriceLowX96);
        console.log('sqrtPriceHighX96: ', postState.sqrtPriceHighX96);

        params.amountIn = 1e18;

        // No more liquidity left to swap in this direction
        vm.expectRevert(SOT.SOT__getLiquidityQuote_zeroAmountOut.selector);
        (amountInUsed, amountOut) = pool.swap(params);

        params.isZeroToOne = false;
        params.swapTokenOut = address(token0);

        // It should be possible to make another swap in the reverse direction
        (amountInUsed, amountOut) = pool.swap(params);

        postState = getPoolState();

        assertNotEq(amountInUsed, 0, 'amountInUsed Right Direction');
        assertNotEq(amountOut, 0, 'amountOut Right Direction');
        assertNotEq(postState.sqrtSpotPriceX96, postState.sqrtPriceLowX96, 'Wrong sqrt spot price update');
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

        bytes memory quote = getEOASignedQuote(_getSensibleSOTParams(), EOASignerPrivateKey);

        // Test Swap with EOA Signer ( but corrupted data )
        // NOTE: if abi.encodePacked is used here instead of abi.encode, the test will fail
        // @audit: verify if these kind of quote manipulations are safe in the SOT.
        SovereignPoolSwapContextData memory data = SovereignPoolSwapContextData({
            externalContext: abi.encode(quote, bytes('random')),
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

        // Revert because the data is corrupted
        vm.expectRevert();
        pool.swap(params);

        // Data fixed, swap should work now.
        data.externalContext = quote;
        uint256 gasUsed = gasleft();
        (uint256 amountInUsed, uint256 amountOut) = pool.swap(params);
        gasUsed = gasUsed - gasleft();
        console.log('gas: ', gasUsed);

        // TODO: replace these with exact math tests
        assertNotEq(amountInUsed, 0, 'amountInUsed 0');
        assertNotEq(amountOut, 0, 'amountOut 0');
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

        SolverOrderType memory sotParams = _getSensibleSOTParams();
        sotParams.expectedFlag = 1;

        data.externalContext = getEOASignedQuote(sotParams, EOASignerPrivateKey);

        (uint256 amountInUsed, uint256 amountOut) = pool.swap(params);

        assertNotEq(amountInUsed, 0, 'amountInUsed 0');
        assertNotEq(amountOut, 0, 'amountOut 0');
    }

    function test_swap_amm_singleSidedLiquidity() public {
        sot.withdrawLiquidity(5e18, 10_000e18, address(this), 0, 0);

        (uint256 amount0, uint256 amount1) = pool.getReserves();
        assertEq(amount0 + amount1, 0, 'pool not empty');

        // Depositing single sided liquidity
        // One unit of token1 is necessary, so that it can be concentrated to infinity
        // when spotPrice = spotPriceLow. Without this, the effective liquidity becomes 0.
        sot.depositLiquidity(5e18, 1, 0, 0);

        (amount0, amount1) = pool.getReserves();

        assertEq(amount0, 5e18, 'amount0');
        assertEq(amount1, 1, 'amount1');

        SolverOrderType memory sotParams = _getSensibleSOTParams();

        (, uint160 sqrtSpotPriceLowX96, ) = sot.getAMMState();
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

        assertNotEq(sot.effectiveAMMLiquidity(), 0, 'effectiveAMMLiquidity');

        (amount0, amount1) = pool.getReserves();

        // Assert that amount1 reserves are empty
        assertEq(amount0, 5e18, 'amount0');
        // TODO: Needs to be changed back to 2, after Sovereign Pool fix
        assertEq(amount1, 1, 'amount1');

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
        // TODO: Check solverWriteSlot everywhere
        // checkSolverWriteSlot(preSolverWriteSlot, sot.solverWriteSlot());
    }

    function test_swap_solver_swapMathWithFee() public {
        // Excess solver feeInBips
        vm.expectRevert(SOT.SOT__setSolverFeeInBips_invalidSolverFee.selector);
        sot.setSolverFeeInBips(101, 5);

        vm.expectRevert(SOT.SOT__setSolverFeeInBips_invalidSolverFee.selector);
        sot.setSolverFeeInBips(5, 101);

        // Correct solver feeInBips: token0 = 0.1%, token1 = 0.5%
        sot.setSolverFeeInBips(10, 50);

        (, uint16 solverFeeBipsToken0, uint16 solverFeeBipsToken1, ) = sot.solverReadSlot();

        assertEq(solverFeeBipsToken0, 10, 'solverFeeBipsToken0');
        assertEq(solverFeeBipsToken1, 50, 'solverFeeBipsToken1');

        // Test Swap with Contract Signer
        SolverOrderType memory sotParams = _getSensibleSOTParams();
        SovereignPoolSwapContextData memory data = SovereignPoolSwapContextData({
            externalContext: mockSigner.getSignedQuote(sotParams),
            verifierContext: bytes(''),
            swapCallbackContext: bytes(''),
            swapFeeModuleContext: bytes('1')
        });

        PoolState memory preState = getPoolState();
        uint256 amountIn = 1e18;

        SovereignPoolSwapParams memory params = SovereignPoolSwapParams({
            isSwapCallback: false,
            isZeroToOne: true,
            amountIn: amountIn,
            amountOutMin: 0,
            recipient: makeAddr('RECIPIENT'),
            deadline: block.timestamp + 2,
            swapTokenOut: address(token1),
            swapContext: data
        });

        // amountInWithoutFee = 1e18 * [1e4 / (1e4 + 10)]
        uint256 amountInWithoutFee = 999000999000999000;

        // 1% of all fees
        vm.prank(pool.poolManager());
        pool.setPoolManagerFeeBips(100);
        uint256 poolManagerFee = (amountIn - amountInWithoutFee) / 100;

        // TODO: add amountInUsed and amountOut checks everywhere
        pool.swap(params);
        PoolState memory postState = getPoolState();

        PoolState memory expectedState = PoolState({
            reserve0: preState.reserve0 + amountIn - poolManagerFee,
            reserve1: preState.reserve1 - amountInWithoutFee * 1980,
            sqrtSpotPriceX96: getSqrtPriceX96(2005 * (10 ** feedToken0.decimals()), 1 * (10 ** feedToken1.decimals())),
            sqrtPriceLowX96: preState.sqrtPriceLowX96,
            sqrtPriceHighX96: preState.sqrtPriceHighX96,
            managerFee0: preState.managerFee0 + poolManagerFee,
            managerFee1: preState.managerFee1 + 0
        });

        checkPoolState(expectedState, postState);

        preState = postState;
        amountIn = 9e8;
        params.isZeroToOne = false;
        params.swapTokenOut = address(token0);
        params.amountIn = amountIn;

        sotParams.nonce = 55;
        data.externalContext = mockSigner.getSignedQuote(sotParams);

        // Check the math in the other direction
        pool.swap(params);

        postState = getPoolState();

        amountInWithoutFee = 895522388;
        poolManagerFee = (amountIn - amountInWithoutFee) / 100;

        expectedState.reserve0 = preState.reserve0 - amountInWithoutFee / 2000;
        expectedState.reserve1 = preState.reserve1 + amountIn - poolManagerFee;
        expectedState.managerFee0 = preState.managerFee0 + 0;
        expectedState.managerFee1 = preState.managerFee1 + poolManagerFee;

        checkPoolState(expectedState, postState);
    }

    function test_swap_invalidFeePath() public {
        sot.setSolverFeeInBips(10, 50);

        // Solver Swap, amm fee path
        SovereignPoolSwapContextData memory data = SovereignPoolSwapContextData({
            externalContext: mockSigner.getSignedQuote(_getSensibleSOTParams()),
            verifierContext: bytes(''),
            swapCallbackContext: bytes(''),
            swapFeeModuleContext: bytes('')
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

        vm.expectRevert(SOT.SOT__getLiquidityQuote_invalidFeePath.selector);
        pool.swap(params);

        // AMM Swap, solver fee path
        data.externalContext = bytes('');
        data.swapFeeModuleContext = bytes('1');

        vm.expectRevert(SOT.SOT__getLiquidityQuote_invalidFeePath.selector);
        pool.swap(params);

        data.externalContext = bytes('');
        data.swapFeeModuleContext = bytes('');
        (uint256 amountInUsed, uint256 amountOut) = pool.swap(params);

        assertNotEq(amountInUsed, 0, 'amountInUsed');
        assertNotEq(amountOut, 0, 'amountOut');
    }

    function test_swap_solver_multipleQuotes() public {
        // Initial block timestamp set to 1000
        vm.warp(1000);
        feedToken0.updateAnswer(2000e8);
        feedToken1.updateAnswer(1e8);

        (uint8 maxAllowedQuotes, , , ) = sot.solverReadSlot();
        assertEq(maxAllowedQuotes, 2, 'maxAllowedQuotes 1');

        vm.expectRevert(SOT.SOT__setMaxAllowedQuotes_invalidMaxAllowedQuotes.selector);
        sot.setMaxAllowedQuotes(57);

        sot.setMaxAllowedQuotes(0);
        (maxAllowedQuotes, , , ) = sot.solverReadSlot();

        assertEq(maxAllowedQuotes, 0, 'maxAllowedQuotes 2');

        SolverOrderType memory sotParams = _getSensibleSOTParams();
        sotParams.signatureTimestamp = (block.timestamp - 5).toUint32();

        SovereignPoolSwapContextData memory data = SovereignPoolSwapContextData({
            externalContext: mockSigner.getSignedQuote(sotParams),
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

        vm.expectRevert(SOT.SOT__getLiquidityQuote_maxSolverQuotesExceeded.selector);
        pool.swap(params);

        sot.setMaxAllowedQuotes(3);

        // First Swap: Discounted
        PoolState memory preState = getPoolState();

        pool.swap(params);

        PoolState memory postState = getPoolState();

        SolverWriteSlot memory expectedSolverWriteSlot = SolverWriteSlot({
            lastProcessedBlockQuoteCount: 1,
            feeGrowthInPipsToken0: 500,
            feeMaxToken0: 100,
            feeMinToken0: 10,
            feeGrowthInPipsToken1: 500,
            feeMaxToken1: 100,
            feeMinToken1: 10,
            lastStateUpdateTimestamp: block.timestamp.toUint32(),
            lastProcessedQuoteTimestamp: block.timestamp.toUint32(),
            lastProcessedSignatureTimestamp: block.timestamp.toUint32() - 5,
            alternatingNonceBitmap: 2
        });

        PoolState memory expectedState = PoolState({
            reserve0: preState.reserve0 + 1e18,
            reserve1: preState.reserve1 - 1e18 * 1980,
            sqrtSpotPriceX96: getSqrtPriceX96(2005 * (10 ** feedToken0.decimals()), 1 * (10 ** feedToken1.decimals())),
            sqrtPriceLowX96: preState.sqrtPriceLowX96,
            sqrtPriceHighX96: preState.sqrtPriceHighX96,
            managerFee0: 0,
            managerFee1: 0
        });

        SolverWriteSlot memory solverWriteSlot = getSolverWriteSlot();

        checkSolverWriteSlot(solverWriteSlot, expectedSolverWriteSlot);
        checkPoolState(expectedState, postState);

        // Invalid quote is sent in between
        sotParams.nonce = 0;
        sotParams.signatureTimestamp = (block.timestamp + 5).toUint32();
        data.externalContext = mockSigner.getSignedQuote(sotParams);

        vm.expectRevert(SOTParams.SOTParams__validateBasicParams_invalidSignatureTimestamp.selector);
        pool.swap(params);

        //  A more updated quote is sent, but should still be considered base
        sotParams.signatureTimestamp = (block.timestamp - 3).toUint32();
        sotParams.solverPriceX192Base = 2001 << 192;
        sotParams.solverPriceX192Discounted = 1990 << 192;
        sotParams.sqrtSpotPriceX96New = getSqrtPriceX96(
            2003 * (10 ** feedToken0.decimals()),
            1 * (10 ** feedToken1.decimals())
        );

        data.externalContext = mockSigner.getSignedQuote(sotParams);
        params.amountIn = 2e18;

        // Second Swap: Base
        preState = postState;
        pool.swap(params);
        postState = getPoolState();

        expectedState.reserve0 = preState.reserve0 + 2e18;
        expectedState.reserve1 = preState.reserve1 - 2e18 * 2001;

        checkPoolState(expectedState, postState);

        expectedSolverWriteSlot.lastProcessedBlockQuoteCount = 2;
        expectedSolverWriteSlot.alternatingNonceBitmap = 3;

        solverWriteSlot = getSolverWriteSlot();

        checkSolverWriteSlot(solverWriteSlot, expectedSolverWriteSlot);

        // Third Swap: Base
        sotParams.nonce = 2;
        sotParams.signatureTimestamp = (block.timestamp - 1).toUint32();
        sotParams.solverPriceX192Base = 2002 << 192;
        sotParams.solverPriceX192Discounted = 1998 << 192;
        sotParams.sqrtSpotPriceX96New = getSqrtPriceX96(
            2004 * (10 ** feedToken0.decimals()),
            1 * (10 ** feedToken1.decimals())
        );

        data.externalContext = mockSigner.getSignedQuote(sotParams);
        params.amountIn = 3e18;
        params.isZeroToOne = false;
        params.swapTokenOut = address(token0);

        preState = postState;
        pool.swap(params);
        postState = getPoolState();
        solverWriteSlot = getSolverWriteSlot();

        expectedState.reserve0 = preState.reserve0 - uint256(Math.mulDiv(3e18, 1 << 192, 2002 << 192));
        expectedState.reserve1 = preState.reserve1 + 3e18;

        expectedSolverWriteSlot.lastProcessedBlockQuoteCount = 3;
        expectedSolverWriteSlot.alternatingNonceBitmap = 7;

        checkPoolState(expectedState, postState);
        checkSolverWriteSlot(expectedSolverWriteSlot, solverWriteSlot);

        // Fourth Swap: Max quotes exceeded should revert
        sotParams.nonce = 3;
        data.externalContext = mockSigner.getSignedQuote(sotParams);

        vm.expectRevert(SOT.SOT__getLiquidityQuote_maxSolverQuotesExceeded.selector);
        pool.swap(params);

        // Next Block
        vm.warp(1001);

        // Older than the last processed signature timestamp, should be treated as base.
        sotParams = _getSensibleSOTParams();
        sotParams.signatureTimestamp = (block.timestamp - 10).toUint32();
        sotParams.expectedFlag = 1;

        data.externalContext = mockSigner.getSignedQuote(sotParams);

        expectedSolverWriteSlot = getSolverWriteSlot();
        preState = getPoolState();

        params.isZeroToOne = true;
        params.amountIn = 1e10;
        params.swapTokenOut = address(token1);
        pool.swap(params);

        postState = getPoolState();
        solverWriteSlot = getSolverWriteSlot();

        expectedSolverWriteSlot.alternatingNonceBitmap = 5;
        expectedSolverWriteSlot.lastProcessedBlockQuoteCount = 1;
        expectedSolverWriteSlot.lastProcessedQuoteTimestamp = block.timestamp.toUint32();
        expectedSolverWriteSlot.lastStateUpdateTimestamp = block.timestamp.toUint32() - 1;
        expectedSolverWriteSlot.lastProcessedSignatureTimestamp = block.timestamp.toUint32() - 6;

        expectedState.reserve0 = preState.reserve0 + params.amountIn;
        expectedState.reserve1 = preState.reserve1 - params.amountIn * 2000;

        checkSolverWriteSlot(solverWriteSlot, expectedSolverWriteSlot);
        checkPoolState(expectedState, postState);

        // The second quote in the new block has a more updated timestamp, should be treated as discounted
        sotParams.signatureTimestamp = (block.timestamp - 2).toUint32();
        sotParams.expectedFlag = 0;
        sotParams.solverPriceX192Base = 2002 << 192;
        sotParams.solverPriceX192Discounted = 1997 << 192;
        sotParams.sqrtSpotPriceX96New = getSqrtPriceX96(
            2004 * (10 ** feedToken0.decimals()),
            1 * (10 ** feedToken1.decimals())
        );

        data.externalContext = mockSigner.getSignedQuote(sotParams);

        expectedSolverWriteSlot = getSolverWriteSlot();
        preState = getPoolState();

        params.isZeroToOne = true;
        params.amountIn = 1e10;
        params.swapTokenOut = address(token1);
        pool.swap(params);

        postState = getPoolState();
        solverWriteSlot = getSolverWriteSlot();

        expectedSolverWriteSlot.alternatingNonceBitmap = 7;
        expectedSolverWriteSlot.lastProcessedBlockQuoteCount = 2;
        expectedSolverWriteSlot.lastProcessedQuoteTimestamp = block.timestamp.toUint32();
        expectedSolverWriteSlot.lastStateUpdateTimestamp = block.timestamp.toUint32();
        expectedSolverWriteSlot.lastStateUpdateTimestamp = block.timestamp.toUint32();
        expectedSolverWriteSlot.lastProcessedSignatureTimestamp = block.timestamp.toUint32() - 2;

        expectedState.reserve0 = preState.reserve0 + params.amountIn;
        expectedState.reserve1 = preState.reserve1 - params.amountIn * 1997;
        expectedState.sqrtSpotPriceX96 = getSqrtPriceX96(
            2004 * (10 ** feedToken0.decimals()),
            1 * (10 ** feedToken1.decimals())
        );

        checkSolverWriteSlot(solverWriteSlot, expectedSolverWriteSlot);
        checkPoolState(expectedState, postState);
    }

    function test_depositLiquidity() public {
        // Deposit liquidity
        sot.depositLiquidity(1, 1, 0, 0);

        (uint256 reserve0, uint256 reserve1) = pool.getReserves();
        assertEq(reserve0, 5e18 + 1, 'reserve0');
        assertEq(reserve1, 10_000e18 + 1, 'reserve1');

        // Deposit with any other address except liquidity provider.
        vm.startPrank(address(makeAddr('NOT_LIQUIDITY_PROVIDER')));
        vm.expectRevert(SOT.SOT__onlyLiquidityProvider.selector);
        sot.depositLiquidity(1, 1, 0, 0);
        vm.stopPrank();

        // Burn all tokens
        token0.transfer(address(1), token0.balanceOf(address(this)));
        token1.transfer(address(1), token1.balanceOf(address(this)));

        vm.expectRevert('ERC20: transfer amount exceeds balance');
        sot.depositLiquidity(1, 1, 0, 0);
    }

    function test_withdrawLiquidity() public {
        // Withdraw with any other address except liquidity provider.
        vm.startPrank(address(makeAddr('NOT_LIQUIDITY_PROVIDER')));
        vm.expectRevert(SOT.SOT__onlyLiquidityProvider.selector);
        sot.withdrawLiquidity(1, 1, address(this), 0, 0);
        vm.stopPrank();

        // Withdraw liquidity to liquidity provider address
        sot.withdrawLiquidity(5e18, 10_000e18, makeAddr('RECEIVER'), 0, 0);

        assertEq(token0.balanceOf(makeAddr('RECEIVER')), 5e18, 'balance0');
        assertEq(token1.balanceOf(makeAddr('RECEIVER')), 10_000e18, 'balance0');

        (uint256 reserve0, uint256 reserve1) = pool.getReserves();
        assertEq(reserve0, 0, 'reserve0');
        assertEq(reserve1, 0, 'reserve1');

        // Withdraw liquidity again
        vm.expectRevert(SovereignPool.SovereignPool__withdrawLiquidity_insufficientReserve0.selector);
        sot.withdrawLiquidity(5e18, 10_000e18, address(this), 0, 0);
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

    function test_onlySpotPriceRange() public {
        uint256 token0Base = 10 ** feedToken0.decimals();
        uint256 token1Base = 10 ** feedToken1.decimals();

        uint160 sqrtPrice1991 = getSqrtPriceX96(1991 * token0Base, 1 * token1Base);
        uint160 sqrtPrice1999 = getSqrtPriceX96(1999 * token0Base, 1 * token1Base);
        uint160 sqrtPrice2000 = getSqrtPriceX96(2000 * token0Base, 1 * token1Base);
        uint160 sqrtPrice2001 = getSqrtPriceX96(2001 * token0Base, 1 * token1Base);
        uint160 sqrtPrice2005 = getSqrtPriceX96(2005 * token0Base, 1 * token1Base);

        // Spot price range is exact, deposit shouldn't revert
        sot.depositLiquidity(1, 1, sqrtPrice1991, sqrtPrice2005);

        (uint256 reserve0, uint256 reserve1) = pool.getReserves();
        assertEq(reserve0, 5e18 + 1, 'reserve0');
        assertEq(reserve1, 10_000e18 + 1, 'reserve1');

        // Spot price is out of range, deposit should revert
        vm.expectRevert(
            abi.encodeWithSelector(SOT.SOT__setPriceBounds_invalidSqrtSpotPriceX96.selector, sqrtPrice2000)
        );
        sot.depositLiquidity(1, 1, sqrtPrice2001, sqrtPrice2005);

        // Exact spot price range for setPriceBounds, should work
        sot.setPriceBounds(sqrtPrice1999, sqrtPrice2001, sqrtPrice1991, sqrtPrice2005);
        (uint160 sqrtSpotPriceX96, uint160 sqrtPriceLowX96, uint160 sqrtPriceHighX96) = sot.getAMMState();

        assertEq(sqrtSpotPriceX96, sqrtPrice2000, 'sqrtSpotPriceX96');
        assertEq(sqrtPriceLowX96, sqrtPrice1999, 'sqrtPriceLowX96');
        assertEq(sqrtPriceHighX96, sqrtPrice2001, 'sqrtPriceHighX96');

        // Spot price is out of range, setPriceBounds should revert
        vm.expectRevert(
            abi.encodeWithSelector(SOT.SOT__setPriceBounds_invalidSqrtSpotPriceX96.selector, sqrtPrice2000)
        );
        sot.setPriceBounds(sqrtPrice1999, sqrtPrice2005, sqrtPrice1991, sqrtPrice1999);

        // (0,0) bypasses all checks
        sot.withdrawLiquidity(1e18, 1e18, address(this), 0, 0);
    }

    function test_computeSwapStep() public {
        (uint160 sqrtSpotPriceX96, uint160 sqrtPriceLowX96, uint160 sqrtPriceHighX96) = sot.getAMMState();

        bool isZeroToOne = false;
        uint160 sqrtSpotPriceX96New;
        uint256 amountIn = 1e18;
        uint256 amountInFilled;
        uint256 amountOut;

        sot.depositLiquidity(5e18, 10_000e18, 0, 0);

        uint128 effectiveLiquidity = sot.effectiveAMMLiquidity();

        (sqrtSpotPriceX96New, amountInFilled, amountOut, ) = SwapMath.computeSwapStep(
            sqrtSpotPriceX96,
            isZeroToOne ? sqrtPriceLowX96 : sqrtPriceHighX96,
            effectiveLiquidity,
            amountIn.toInt256(), // always exact input swap
            0 // fees have already been deducted
        );

        isZeroToOne = !isZeroToOne;

        (sqrtSpotPriceX96New, amountInFilled, amountOut, ) = SwapMath.computeSwapStep(
            sqrtSpotPriceX96New,
            isZeroToOne ? sqrtPriceLowX96 : sqrtPriceHighX96,
            effectiveLiquidity,
            amountOut.toInt256(), // always exact input swap
            0 // fees have already been deducted
        );

        assertApproxEqRel(sqrtSpotPriceX96, sqrtSpotPriceX96New, 1, 'sqrtSpotPriceX96New');
        assertGe(amountIn, amountOut, 'amountIn');
    }
}

/**
    Test Cases:

    ==> Solver Swap 
        * [*] All types of signatures, failure and edge cases
        * [ ] Multiple quotes in the same block 
            - [*] Discounted/Non-Discounted
            - [*] Valid/Invalid
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
        * [*] Calculation of Manager Fee
        * [*] Correct amountIn and out calculations 
        * [*] Solver fee in BIPS is applied correctly
        * [*] Swap Math is correct, amountOut calculations are correct
        * [*] Max quotes in a block
        * [ ] Expired quotes should not be allowed 

    ==> AMM Swap
        * [*] Effects on AMM when very large swaps drain pool in one token, spot price etc.
        * [*] Valid/Invalid fee paths
        * [ ] AMM Math is as expected
        * [ ] Liquidity is calculated correctly
        * [ ] Set price bounds shifts liquidity correctly
        * [ ] Fee growth is correct, pool is soft locked before solver swap
        * [ ] No AMM swap is every able to change Solver Write Slot [invariant]
        * [*] Single Sided Liquidity
    
    ==> General Ops
        * [*] Pause/Unpause works as expected [done]
        * [ ] Constructor sets all values correctly
        * [ ] Get Reserves at Price function is correct
        * [ ] All important functions are reentrancy protected
        * [ ] Manager is able to withdraw fee from Sovereign Pool
        * [ ] Critical Manager operations are timelocked
        * [*] Check spot price manipulation on deposit/withdraw/setPriceBounds
        * [*] Tests for depositLiquidity
        * [*] Tests for withdrawLiquidity
    
    ==> Gas
        * [ ] Prepare setup for correct gas reports
        * [ ] Solvers should do maximum 2 storage writes in SOT

    ==> Imp
        * [ ] Fuzz at edges of liquidity to make sure there are no path independence issues
        * [ ] Write tests for LiquidityAmounts library especially at edges
        * [ ] What happens when spotPrice = spotPriceLow = spotPriceHigh, quote becomes infinite.
        * [ ] Check if maxVolume per quote is enforced in amountOut
        * [ ] Without an SOT quote or deposits, the amm liquidity should never change by just amm swaps 
*/
