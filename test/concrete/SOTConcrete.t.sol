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

import { SOT, ALMLiquidityQuoteInput } from '../../src/SOT.sol';
import { SOTParams } from '../../src/libraries/SOTParams.sol';
import { SOTOracle } from '../../src/SOTOracle.sol';
import { SOTConstructorArgs, SolverOrderType, SolverWriteSlot, SolverReadSlot } from '../../src/structs/SOTStructs.sol';
import { SOTConstants } from '../../src/libraries/SOTConstants.sol';
import { TightPack } from '../../src/libraries/utils/TightPack.sol';

import { SOTBase } from '../base/SOTBase.t.sol';

contract SOTConcreteTest is SOTBase {
    using SafeCast for uint256;

    event LogBytes(bytes data);

    function setUp() public virtual override {
        super.setUp();

        // Reserves in the ratio 1: 2000
        _setupBalanceForUser(address(this), address(token0), type(uint256).max);
        _setupBalanceForUser(address(this), address(token1), type(uint256).max);

        sot.depositLiquidity(5e18, 10_000e18, 0, 0);

        // Max volume for token0 ( Eth ) is 100, and for token1 ( USDC ) is 20,000
        vm.prank(address(this));
        sot.setMaxTokenVolumes(100e18, 20_000e18);
        sot.setMaxAllowedQuotes(2);

        sot.setMaxOracleDeviationBips(sotImmutableMaxOracleDeviationBound, sotImmutableMaxOracleDeviationBound);
    }

    function test_managerOperations() public {
        vm.startPrank(makeAddr('NOT_MANAGER'));

        vm.expectRevert(SOT.SOT__onlyManager.selector);
        sot.setManager(makeAddr('MANAGER'));

        vm.expectRevert(SOT.SOT__onlyManager.selector);
        sot.setSigner(makeAddr('SIGNER'));

        vm.expectRevert(SOT.SOT__onlyManager.selector);
        sot.setMaxTokenVolumes(500, 500);

        vm.stopPrank();

        sot.setSigner(makeAddr('SIGNER'));

        (, , , , , , address signer) = sot.solverReadSlot();
        assertEq(signer, makeAddr('SIGNER'), 'signer');

        sot.setMaxTokenVolumes(500, 500);
        (uint256 maxToken0VolumeToQuote, ) = sot.maxTokenVolumes();
        assertEq(maxToken0VolumeToQuote, 500, 'maxTokenVolume0');
        assertEq(maxToken0VolumeToQuote, 500, 'maxTokenVolume1');

        sot.setManager(makeAddr('MANAGER'));
        assertEq(sot.manager(), makeAddr('MANAGER'), 'manager');
    }

    function test_onlyPool() public {
        vm.expectRevert(SOT.SOT__onlyPool.selector);
        sot.onSwapCallback(false, 0, 0);

        vm.expectRevert(SOT.SOT__onlyPool.selector);
        sot.onDepositLiquidityCallback(0, 0, bytes(''));

        vm.expectRevert(SOT.SOT__onlyPool.selector);
        ALMLiquidityQuoteInput memory poolInput = ALMLiquidityQuoteInput(
            false,
            0,
            0,
            address(0),
            address(0),
            address(0)
        );
        sot.getLiquidityQuote(poolInput, bytes(''), bytes(''));
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

        (uint256 amountInUsed, uint256 amountOut) = pool.swap(params);
        uint256 postGas = gasleft();
        console.log('gas: ', preGas - postGas);

        PoolState memory postState = getPoolState();

        (uint160 sqrtSpotPriceX96, , ) = sot.getAMMState();

        PoolState memory expectedState = PoolState({
            reserve0: preState.reserve0 + 1e18,
            reserve1: preState.reserve1 - amountOut,
            sqrtSpotPriceX96: sqrtSpotPriceX96,
            sqrtPriceLowX96: preState.sqrtPriceLowX96,
            sqrtPriceHighX96: preState.sqrtPriceHighX96,
            managerFee0: 0,
            managerFee1: 0
        });

        assertEq(amountInUsed, 1e18, 'amountInUsed');
        checkPoolState(expectedState, postState);
    }

    function test_swap_amm_negative_rebase() public {
        // deploy rebase token pool
        SovereignPoolConstructorArgs memory poolArgs = _generateDefaultConstructorArgs();
        poolArgs.isToken0Rebase = true;
        poolArgs.isToken1Rebase = true;
        pool = this.deploySovereignPool(poolArgs);
        sot = deployAndSetDefaultSOT(pool);

        _addToContractsToApprove(address(pool));
        _addToContractsToApprove(address(sot));

        token0.approve(address(sot), 1e26);
        token1.approve(address(sot), 1e26);

        token0.approve(address(pool), 1e26);
        token1.approve(address(pool), 1e26);

        sot.depositLiquidity(5e18, 10_000e18, 0, 0);

        // Max volume for token0 ( Eth ) is 100, and for token1 ( USDC ) is 20,000
        vm.prank(address(this));
        sot.setMaxTokenVolumes(100e18, 20_000e18);
        sot.setMaxAllowedQuotes(2);

        sot.setMaxOracleDeviationBips(sotImmutableMaxOracleDeviationBound, sotImmutableMaxOracleDeviationBound);

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

        uint256 snapshot = vm.snapshot();

        (uint256 amountInUsed, uint256 amountOut) = pool.swap(params);

        (uint160 sqrtSpotPriceX96, , ) = sot.getAMMState();

        vm.revertTo(snapshot);

        vm.startPrank(address(pool));
        token1.transfer(address(1), preState.reserve1 / 2);
        vm.stopPrank();

        (uint256 amountInUsedRebase, uint256 amountOutRebase) = pool.swap(params);

        (uint160 sqrtSpotPriceX96Rebase, , ) = sot.getAMMState();

        assertEq(amountInUsedRebase, amountInUsed, 'amountInUsed');

        assertLe(amountOutRebase, amountOut, 'Amount out');

        assertLe(sqrtSpotPriceX96Rebase, sqrtSpotPriceX96, 'Spot price should decrease more');
    }

    function test_swap_amm_depleteLiquidityInOneToken() public {
        SovereignPoolSwapContextData memory data;
        SovereignPoolSwapParams memory params = SovereignPoolSwapParams({
            isSwapCallback: false,
            isZeroToOne: false,
            amountIn: 1e30, // Swap large amount to deplete 1 token
            amountOutMin: 0,
            recipient: address(this),
            deadline: block.timestamp + 2,
            swapTokenOut: address(token0),
            swapContext: data
        });

        // Deplete liquidity in one token, but spot price reaches the edge
        vm.expectRevert(SOT.SOT___ammSwap_invalidSpotPriceAfterSwap.selector);
        pool.swap(params);

        (, uint160 sqrtPriceLowX96, ) = sot.getAMMState();

        (uint256 amount0, ) = sot.getReservesAtPrice(sqrtPriceLowX96 + 1);
        (uint256 reserve0, ) = pool.getReserves();

        params.isZeroToOne = !params.isZeroToOne;
        params.swapTokenOut = params.isZeroToOne ? address(token1) : address(token0);

        vm.expectRevert(SOT.SOT___ammSwap_invalidSpotPriceAfterSwap.selector);
        pool.swap(params);

        // Extra one is substracted for precision issues
        params.amountIn = amount0 - reserve0 - 1;

        (uint256 amountInUsed, uint256 amountOut) = pool.swap(params);
        PoolState memory postState = getPoolState();

        // Check that sqrt spot price is near the lower bound
        assertApproxEqRel(postState.sqrtSpotPriceX96, postState.sqrtPriceLowX96 + 1, 1, 'Wrong sqrt spot price update');

        console.log('amountInUsed 1: ', amountInUsed);
        console.log('amountOut 1: ', amountOut);
        console.log('reserve0: ', postState.reserve0);
        console.log('reserve1: ', postState.reserve1);
        console.log('sqrtSpotPriceX96: ', postState.sqrtSpotPriceX96);
        console.log('sqrtPriceLowX96: ', postState.sqrtPriceLowX96);
        console.log('sqrtPriceHighX96: ', postState.sqrtPriceHighX96);

        params.amountIn = 1;

        // Trying to swap even 1 amount on the other side results in revert
        vm.expectRevert(SOT.SOT___ammSwap_invalidSpotPriceAfterSwap.selector);
        (amountInUsed, amountOut) = pool.swap(params);

        params.isZeroToOne = !params.isZeroToOne;
        params.swapTokenOut = params.isZeroToOne ? address(token1) : address(token0);
        params.amountIn = 1e18;
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
            reserve1: preState.reserve1 - (1980e18 - 1),
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

        assertEq(amountInUsed, 1e18, 'amountInUsed 0');
        assertEq(amountOut, 1980e18 - 1, 'amountOut 0');
    }

    function test_swap_solver_maxTokenVolume() public {
        sot.setMaxTokenVolumes(type(uint256).max, 500);

        SovereignPoolSwapContextData memory data = SovereignPoolSwapContextData({
            externalContext: mockSigner.getSignedQuote(_getSensibleSOTParams()),
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

        vm.expectRevert(SOTParams.SOTParams__validateBasicParams_excessiveTokenOutAmountRequested.selector);
        pool.swap(params);

        sot.setMaxTokenVolumes(500, type(uint256).max);
        params.isZeroToOne = false;
        params.swapTokenOut = address(token0);
        SolverOrderType memory sotParams = _getSensibleSOTParams();
        sotParams.isZeroToOne = false;
        params.swapContext.externalContext = mockSigner.getSignedQuote(sotParams);

        vm.expectRevert(SOTParams.SOTParams__validateBasicParams_excessiveTokenOutAmountRequested.selector);
        pool.swap(params);

        sot.setMaxTokenVolumes(type(uint256).max, type(uint256).max);
        pool.swap(params);
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

        vm.expectRevert(SOT.SOT___solverSwap_invalidSignature.selector);
        pool.swap(params);
    }

    function test_swap_solver_incorrectSwapDirection() public {
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
            isZeroToOne: false,
            amountIn: 1e18,
            amountOutMin: 0,
            recipient: makeAddr('RECIPIENT'),
            deadline: block.timestamp + 2,
            swapTokenOut: address(token0),
            swapContext: data
        });

        vm.expectRevert(SOTParams.SOTParams__validateBasicParams_incorrectSwapDirection.selector);
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
        // Exactly sqrtPriceLow will cause revert
        sotParams.sqrtSpotPriceX96New = sqrtSpotPriceLowX96 + 1;

        // Update the Oracle so that it allows the spot price to be updated to the edge
        feedToken0.updateAnswer(1500e8);
        sotParams.sqrtSolverPriceX96Discounted = getSqrtPriceX96(
            1500 * (10 ** feedToken0.decimals()),
            1 * (10 ** feedToken1.decimals())
        );
        sotParams.isZeroToOne = false;

        // Set Spot price to priceLow with a minimal SOT
        SovereignPoolSwapContextData memory data = SovereignPoolSwapContextData({
            externalContext: mockSigner.getSignedQuote(sotParams),
            verifierContext: bytes(''),
            swapCallbackContext: bytes(''),
            swapFeeModuleContext: bytes('1')
        });

        // AmountIn is set to 2000, so that amountOut is just 1,
        // to prevent SOT from reverting with amountOut == 0 error
        SovereignPoolSwapParams memory params = SovereignPoolSwapParams({
            isSwapCallback: false,
            isZeroToOne: false,
            amountIn: 2000,
            amountOutMin: 0,
            recipient: makeAddr('RECIPIENT'),
            deadline: block.timestamp + 2,
            swapTokenOut: address(token0),
            swapContext: data
        });

        // Perform SOT swap to update the spot price
        (uint256 amountInUsed, uint256 amountOut) = pool.swap(params);

        assertNotEq(sot.effectiveAMMLiquidity(), 0, 'effectiveAMMLiquidity');

        (amount0, amount1) = pool.getReserves();

        // Assert that amount1 reserves are almost empty
        assertEq(amount0, 5e18 - 1, 'amount0');
        assertEq(amount1, 1 + 2000, 'amount1');

        data.swapFeeModuleContext = bytes('');
        data.externalContext = bytes('');

        params.amountIn = 1e18;
        params.swapContext = data;

        (amountInUsed, amountOut) = pool.swap(params);

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
            reserve1: preState.reserve1 - (1e18 * 2000 - 1),
            sqrtSpotPriceX96: getSqrtPriceX96(2005 * (10 ** feedToken0.decimals()), 1 * (10 ** feedToken1.decimals())),
            sqrtPriceLowX96: preState.sqrtPriceLowX96,
            sqrtPriceHighX96: preState.sqrtPriceHighX96,
            managerFee0: 0,
            managerFee1: 0
        });

        checkPoolState(expectedState, postState);
    }

    function test_swap_solver_swapMathWithFee() public {
        // Excess solver feeInBips
        vm.expectRevert(SOT.SOT__setSolverFeeInBips_invalidSolverFee.selector);
        sot.setSolverFeeInBips(101, 5);

        vm.expectRevert(SOT.SOT__setSolverFeeInBips_invalidSolverFee.selector);
        sot.setSolverFeeInBips(5, 101);

        // Correct solver feeInBips: token0 = 0.1%, token1 = 0.5%
        sot.setSolverFeeInBips(10, 50);

        (, , , , uint16 solverFeeBipsToken0, uint16 solverFeeBipsToken1, ) = sot.solverReadSlot();

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

        pool.swap(params);
        PoolState memory postState = getPoolState();

        PoolState memory expectedState = PoolState({
            reserve0: preState.reserve0 + amountIn - poolManagerFee,
            reserve1: preState.reserve1 - (amountInWithoutFee * 1980 - 1),
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
        sotParams.isZeroToOne = false;
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

        (, uint8 maxAllowedQuotes, , , , , ) = sot.solverReadSlot();
        assertEq(maxAllowedQuotes, 2, 'maxAllowedQuotes 1');

        vm.expectRevert(SOT.SOT__setMaxAllowedQuotes_invalidMaxAllowedQuotes.selector);
        sot.setMaxAllowedQuotes(57);

        sot.setMaxAllowedQuotes(0);
        (, maxAllowedQuotes, , , , , ) = sot.solverReadSlot();

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

        vm.expectRevert(SOT.SOT___solverSwap_maxSolverQuotesExceeded.selector);
        pool.swap(params);

        sot.setMaxAllowedQuotes(3);

        // First Swap: Discounted
        PoolState memory preState = getPoolState();

        pool.swap(params);

        PoolState memory postState = getPoolState();

        SolverWriteSlot memory expectedSolverWriteSlot = SolverWriteSlot({
            lastProcessedBlockQuoteCount: 1,
            feeGrowthE6Token0: 500,
            feeMaxToken0: 100,
            feeMinToken0: 10,
            feeGrowthE6Token1: 500,
            feeMaxToken1: 100,
            feeMinToken1: 10,
            lastStateUpdateTimestamp: block.timestamp.toUint32(),
            lastProcessedQuoteTimestamp: block.timestamp.toUint32(),
            lastProcessedSignatureTimestamp: block.timestamp.toUint32() - 5,
            alternatingNonceBitmap: 2
        });

        PoolState memory expectedState = PoolState({
            reserve0: preState.reserve0 + 1e18,
            reserve1: preState.reserve1 - (1e18 * 1980 - 1),
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
        sotParams.sqrtSolverPriceX96Base = 3544076829374435021495299114820;
        sotParams.sqrtSolverPriceX96Discounted = getSqrtPriceX96(
            1990 * (10 ** feedToken0.decimals()),
            1 * (10 ** feedToken1.decimals())
        );
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
        expectedState.reserve1 = preState.reserve1 - ((2e18 * 2001) - 1);

        checkPoolState(expectedState, postState);

        expectedSolverWriteSlot.lastProcessedBlockQuoteCount = 2;
        expectedSolverWriteSlot.alternatingNonceBitmap = 3;

        solverWriteSlot = getSolverWriteSlot();

        checkSolverWriteSlot(solverWriteSlot, expectedSolverWriteSlot);

        // Third Swap: Base
        sotParams.nonce = 2;
        sotParams.signatureTimestamp = (block.timestamp - 1).toUint32();
        sotParams.sqrtSolverPriceX96Base = getSqrtPriceX96(
            2002 * (10 ** feedToken0.decimals()),
            1 * (10 ** feedToken1.decimals())
        );
        sotParams.sqrtSolverPriceX96Discounted = getSqrtPriceX96(
            1998 * (10 ** feedToken0.decimals()),
            1 * (10 ** feedToken1.decimals())
        );
        sotParams.sqrtSpotPriceX96New = getSqrtPriceX96(
            2004 * (10 ** feedToken0.decimals()),
            1 * (10 ** feedToken1.decimals())
        );
        sotParams.isZeroToOne = false;

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

        vm.expectRevert(SOT.SOT___solverSwap_maxSolverQuotesExceeded.selector);
        pool.swap(params);

        // Next Block
        vm.warp(1001);

        // Older than the last processed signature timestamp, should be treated as base.
        sotParams = _getSensibleSOTParams();
        sotParams.signatureTimestamp = (block.timestamp - 10).toUint32();
        sotParams.expectedFlag = 1;
        sotParams.isZeroToOne = true;

        data.externalContext = mockSigner.getSignedQuote(sotParams);

        expectedSolverWriteSlot = getSolverWriteSlot();
        preState = getPoolState();

        params.isZeroToOne = true;
        params.amountIn = 1e10;
        params.swapTokenOut = address(token1);
        uint256 preGas = gasleft();
        pool.swap(params);
        uint256 postGas = gasleft();

        console.log('gas base solver warm: ', preGas - postGas);

        postState = getPoolState();
        solverWriteSlot = getSolverWriteSlot();

        expectedSolverWriteSlot.alternatingNonceBitmap = 5;
        expectedSolverWriteSlot.lastProcessedBlockQuoteCount = 1;
        expectedSolverWriteSlot.lastProcessedQuoteTimestamp = block.timestamp.toUint32();
        expectedSolverWriteSlot.lastStateUpdateTimestamp = block.timestamp.toUint32() - 1;
        expectedSolverWriteSlot.lastProcessedSignatureTimestamp = block.timestamp.toUint32() - 6;

        expectedState.reserve0 = preState.reserve0 + params.amountIn;
        expectedState.reserve1 = preState.reserve1 - (params.amountIn * 2000 - 1);

        checkSolverWriteSlot(solverWriteSlot, expectedSolverWriteSlot);
        checkPoolState(expectedState, postState);

        // The second quote in the new block has a more updated timestamp, should be treated as discounted
        sotParams.signatureTimestamp = (block.timestamp - 2).toUint32();
        sotParams.expectedFlag = 0;
        sotParams.sqrtSolverPriceX96Base = getSqrtPriceX96(
            2002 * (10 ** feedToken0.decimals()),
            1 * (10 ** feedToken1.decimals())
        );
        sotParams.sqrtSolverPriceX96Discounted = getSqrtPriceX96(
            1997 * (10 ** feedToken0.decimals()),
            1 * (10 ** feedToken1.decimals())
        );
        sotParams.sqrtSpotPriceX96New = getSqrtPriceX96(
            2004 * (10 ** feedToken0.decimals()),
            1 * (10 ** feedToken1.decimals())
        );
        sotParams.isZeroToOne = true;

        data.externalContext = mockSigner.getSignedQuote(sotParams);

        expectedSolverWriteSlot = getSolverWriteSlot();
        preState = getPoolState();

        params.isZeroToOne = true;
        params.amountIn = 1e10;
        params.swapTokenOut = address(token1);

        preGas = gasleft();
        pool.swap(params);
        postGas = gasleft();
        console.log('gas discounted solver warm: ', preGas - postGas);

        postState = getPoolState();
        solverWriteSlot = getSolverWriteSlot();

        expectedSolverWriteSlot.alternatingNonceBitmap = 7;
        expectedSolverWriteSlot.lastProcessedBlockQuoteCount = 2;
        expectedSolverWriteSlot.lastProcessedQuoteTimestamp = block.timestamp.toUint32();
        expectedSolverWriteSlot.lastStateUpdateTimestamp = block.timestamp.toUint32();
        expectedSolverWriteSlot.lastStateUpdateTimestamp = block.timestamp.toUint32();
        expectedSolverWriteSlot.lastProcessedSignatureTimestamp = block.timestamp.toUint32() - 2;

        expectedState.reserve0 = preState.reserve0 + params.amountIn;
        expectedState.reserve1 = preState.reserve1 - (params.amountIn * 1997 - 1);
        expectedState.sqrtSpotPriceX96 = getSqrtPriceX96(
            2004 * (10 ** feedToken0.decimals()),
            1 * (10 ** feedToken1.decimals())
        );

        checkSolverWriteSlot(solverWriteSlot, expectedSolverWriteSlot);
        checkPoolState(expectedState, postState);
    }

    function test_setPriceBounds() public {
        uint256 token0Base = 10 ** feedToken0.decimals();
        uint256 token1Base = 10 ** feedToken1.decimals();

        uint160 sqrtPrice1996 = getSqrtPriceX96(1996 * token0Base, 1 * token1Base);
        uint160 sqrtPrice2000 = getSqrtPriceX96(2000 * token0Base, 1 * token1Base);
        uint160 sqrtPrice2001 = getSqrtPriceX96(2001 * token0Base, 1 * token1Base);
        uint160 sqrtPrice2004 = getSqrtPriceX96(2004 * token0Base, 1 * token1Base);

        vm.expectRevert(SOTParams.SOTParams__validatePriceBounds_invalidPriceBounds.selector);
        sot.setPriceBounds(sqrtPrice2004, sqrtPrice1996, sqrtPrice2000, sqrtPrice2004);

        vm.expectRevert(SOTParams.SOTParams__validatePriceBounds_invalidPriceBounds.selector);
        sot.setPriceBounds(SOTConstants.MIN_SQRT_PRICE - 1, sqrtPrice1996, sqrtPrice2000, sqrtPrice2004);

        vm.expectRevert(SOTParams.SOTParams__validatePriceBounds_invalidPriceBounds.selector);
        sot.setPriceBounds(SOTConstants.MAX_SQRT_PRICE + 1, sqrtPrice1996, sqrtPrice2000, sqrtPrice2004);

        // New sqrt price bounds much include current sqrt spot price
        vm.expectRevert(SOTParams.SOTParams__validatePriceBounds_newSpotPriceOutOfBounds.selector);
        sot.setPriceBounds(sqrtPrice2001, sqrtPrice2004, sqrtPrice2000, sqrtPrice2004);

        uint160 sqrtPriceLowX96;
        uint160 sqrtPriceHighX96;

        {
            (, sqrtPriceLowX96, sqrtPriceHighX96) = sot.getAMMState();

            uint160 sqrtPrice2100 = getSqrtPriceX96(
                2180 * 10 ** feedToken0.decimals(),
                1 * 10 ** feedToken1.decimals()
            );

            _setAMMState(sqrtPrice2100, sqrtPriceLowX96, sqrtPriceHighX96);

            sot.setMaxOracleDeviationBips(100, 100);
            feedToken0.updateAnswer(5000e8);

            uint160 sqrtPrice1980 = getSqrtPriceX96(
                1980 * 10 ** feedToken0.decimals(),
                1 * 10 ** feedToken1.decimals()
            );
            uint160 sqrtPrice2200 = getSqrtPriceX96(
                2200 * 10 ** feedToken0.decimals(),
                1 * 10 ** feedToken1.decimals()
            );

            vm.expectRevert(SOT.SOT__setPriceBounds_spotPriceAndOracleDeviation.selector);
            sot.setPriceBounds(sqrtPrice1980, sqrtPrice2200, 0, 0);

            _setAMMState(sqrtPrice2000, sqrtPriceLowX96, sqrtPriceHighX96);
            feedToken0.updateAnswer(2000e8);
        }

        sot.setPriceBounds(sqrtPrice1996, sqrtPrice2004, sqrtPrice2000, sqrtPrice2004);
        (, sqrtPriceLowX96, sqrtPriceHighX96) = sot.getAMMState();

        // Wolfram Calculations, using uniswap book equations
        // liquidity0 = 223942152100743332644993.439824912284555965182450458024505347
        // liquidity1 = 223494938393435637038291.193984236332870991687954456111819346
        // expectedEffectiveAMMLiquidity = 223494938393435637038291

        assertEq(sot.effectiveAMMLiquidity(), 223494938393435637038291, 'effectiveAMMLiquidity');

        assertEq(sqrtPriceLowX96, sqrtPrice1996, 'sqrtPriceLowX96');
        assertEq(sqrtPriceHighX96, sqrtPrice2004, 'sqrtPriceHighX96');
    }

    function test_depositLiquidity() public {
        // Deposit liquidity
        sot.depositLiquidity(1, 1, 0, 0);

        (uint256 reserve0, uint256 reserve1) = pool.getReserves();
        assertEq(reserve0, 5e18 + 1, 'reserve0');
        assertEq(reserve1, 10_000e18 + 1, 'reserve1');

        sot.depositLiquidity(1, 0, 0, 0);

        (reserve0, reserve1) = pool.getReserves();
        assertEq(reserve0, 5e18 + 2, 'reserve0');
        assertEq(reserve1, 10_000e18 + 1, 'reserve1');

        sot.depositLiquidity(0, 1, 0, 0);

        (reserve0, reserve1) = pool.getReserves();
        assertEq(reserve0, 5e18 + 2, 'reserve0');
        assertEq(reserve1, 10_000e18 + 2, 'reserve1');

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

    function test_depositLiquidity_oracleDeviation() public {
        vm.startPrank(makeAddr('NOT_MANAGER'));
        vm.expectRevert(SOT.SOT__onlyManager.selector);

        sot.setMaxOracleDeviationBips(100, 100);
        vm.stopPrank();

        vm.expectRevert(SOT.SOT__setMaxOracleDeviationBips_exceedsMaxDeviationBounds.selector);
        sot.setMaxOracleDeviationBips(uint16(5001), uint16(1));

        vm.expectRevert(SOT.SOT__setMaxOracleDeviationBips_exceedsMaxDeviationBounds.selector);
        sot.setMaxOracleDeviationBips(uint16(1), uint16(5001));

        // 1% deviation in sqrtSpotPrices means ~2% deviation in real prices
        sot.setMaxOracleDeviationBips(100, 100);
        (, , uint16 maxOracleDeviationBipsLower, uint16 maxOracleDeviationBipsUpper, , , ) = sot.solverReadSlot();

        assertEq(maxOracleDeviationBipsLower, 100, 'maxOracleDeviationBipsLower');
        assertEq(maxOracleDeviationBipsUpper, 100, 'maxOracleDeviationBipsUpper');

        // Spot price falls within the deviation
        {
            (, uint160 sqrtPriceLowX96, uint160 sqrtPriceHighX96) = sot.getAMMState();

            uint160 sqrtPrice5099 = getSqrtPriceX96(
                5049 * 10 ** feedToken0.decimals(),
                1 * 10 ** feedToken1.decimals()
            );

            _setAMMState(sqrtPrice5099, sqrtPriceLowX96, sqrtPriceHighX96);
        }

        feedToken0.updateAnswer(5000e8);

        // This should not revert
        sot.depositLiquidity(1, 1, 0, 0);
        (uint256 reserve0, uint256 reserve1) = pool.getReserves();
        assertEq(reserve0, 5e18 + 1, 'reserve0');
        assertEq(reserve1, 10_000e18 + 1, 'reserve1');

        {
            (, uint160 sqrtPriceLowX96, uint160 sqrtPriceHighX96) = sot.getAMMState();

            uint160 sqrtPrice5101 = getSqrtPriceX96(
                5101 * 10 ** feedToken0.decimals(),
                1 * 10 ** feedToken1.decimals()
            );

            _setAMMState(sqrtPrice5101, sqrtPriceLowX96, sqrtPriceHighX96);
        }

        // Should revert, as deviation is greater than 2% on the higher side
        vm.expectRevert(SOT.SOT__depositLiquidity_spotPriceAndOracleDeviation.selector);
        sot.depositLiquidity(1, 1, 0, 0);

        {
            (, uint160 sqrtPriceLowX96, uint160 sqrtPriceHighX96) = sot.getAMMState();

            uint160 sqrtPrice4899 = getSqrtPriceX96(
                4899 * 10 ** feedToken0.decimals(),
                1 * 10 ** feedToken1.decimals()
            );

            _setAMMState(sqrtPrice4899, sqrtPriceLowX96, sqrtPriceHighX96);
        }

        // Should revert, as deviation is greater than 2% on the lower side
        vm.expectRevert(SOT.SOT__depositLiquidity_spotPriceAndOracleDeviation.selector);
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

    function test_withdrawLiquidity_cappedEffectiveLiquidity() public {
        sot.depositLiquidity(0, 1e23, 0, 0);

        uint128 preLiquidity = sot.effectiveAMMLiquidity();

        {
            uint160 sqrtSpotPriceX96 = getSqrtPriceX96(
                90000 * 10 ** feedToken0.decimals(),
                1 * 10 ** feedToken1.decimals()
            );

            uint160 sqrtPriceLowX96 = getSqrtPriceX96(
                80000 * 10 ** feedToken0.decimals(),
                1 * 10 ** feedToken1.decimals()
            );

            uint160 sqrtPriceHighX96 = getSqrtPriceX96(
                91000 * 10 ** feedToken0.decimals(),
                1 * 10 ** feedToken1.decimals()
            );

            _setAMMState(sqrtSpotPriceX96, sqrtPriceLowX96, sqrtPriceHighX96);
        }

        sot.withdrawLiquidity(1, 0, address(this), 0, 0);

        uint128 postLiquidity = sot.effectiveAMMLiquidity();
        console.log('preLiquidity: ', preLiquidity);
        console.log('postLiquidity: ', postLiquidity);

        assertEq(preLiquidity, postLiquidity, 'effectiveAMMLiquidity Capped');
    }

    function test_pause() public {
        (bool isPaused, , , , , , ) = sot.solverReadSlot();
        // Default SOT is unpaused
        assertFalse(isPaused, 'isPaused error 1');

        // Set to the same value again
        sot.setPause(false);
        (isPaused, , , , , , ) = sot.solverReadSlot();
        assertFalse(isPaused, 'isPaused error 2');

        // Pause the SOT. At this point SOT has (5e18, 10_000e18) liquidity
        sot.setPause(true);
        (isPaused, , , , , , ) = sot.solverReadSlot();
        assertTrue(isPaused, 'isPaused error 3');

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
        (isPaused, , , , , , ) = sot.solverReadSlot();
        assertFalse(isPaused, 'isPaused error 4');

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
            abi.encodeWithSelector(SOT.SOT___checkSpotPriceRange_invalidSqrtSpotPriceX96.selector, sqrtPrice2000)
        );
        sot.depositLiquidity(1, 1, sqrtPrice2001, sqrtPrice2005);

        // Revert if there are bounds set and we pass either of the values as zero
        vm.expectRevert(SOT.SOT___checkSpotPriceRange_invalidBounds.selector);
        sot.depositLiquidity(1, 1, 0, 1);

        // Exact spot price range for setPriceBounds, should work
        sot.setPriceBounds(sqrtPrice1999, sqrtPrice2001, sqrtPrice1991, sqrtPrice2005);
        (uint160 sqrtSpotPriceX96, uint160 sqrtPriceLowX96, uint160 sqrtPriceHighX96) = sot.getAMMState();

        assertEq(sqrtSpotPriceX96, sqrtPrice2000, 'sqrtSpotPriceX96');
        assertEq(sqrtPriceLowX96, sqrtPrice1999, 'sqrtPriceLowX96');
        assertEq(sqrtPriceHighX96, sqrtPrice2001, 'sqrtPriceHighX96');

        // Spot price is out of range, setPriceBounds should revert
        vm.expectRevert(
            abi.encodeWithSelector(SOT.SOT___checkSpotPriceRange_invalidSqrtSpotPriceX96.selector, sqrtPrice2000)
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

    function test_getSwapFeeInBips_ammSwap() public {
        SolverWriteSlot memory solverWriteSlot = getSolverWriteSlot();

        solverWriteSlot.lastProcessedSignatureTimestamp = uint32(block.timestamp);

        // for token0
        solverWriteSlot.feeGrowthE6Token0 = 10;
        solverWriteSlot.feeMinToken0 = 20;
        solverWriteSlot.feeMaxToken0 = 1000;

        // for token1
        solverWriteSlot.feeGrowthE6Token1 = 100;
        solverWriteSlot.feeMinToken1 = 10;
        solverWriteSlot.feeMaxToken1 = 1000;

        _setSolverWriteSlot(solverWriteSlot);

        solverWriteSlot = getSolverWriteSlot();

        assertEq(solverWriteSlot.feeGrowthE6Token0, 10);

        uint256 snapshot = vm.snapshot();

        vm.warp(block.timestamp + 100);

        // for token0
        uint32 feeInBips = solverWriteSlot.feeMinToken0 +
            uint32(
                Math.mulDiv(
                    solverWriteSlot.feeGrowthE6Token0,
                    (block.timestamp - solverWriteSlot.lastProcessedSignatureTimestamp),
                    100
                )
            );

        if (feeInBips > solverWriteSlot.feeMaxToken0) {
            feeInBips = solverWriteSlot.feeMaxToken0;
        }

        vm.prank(address(pool));
        SwapFeeModuleData memory swapFeeModuleData = sot.getSwapFeeInBips(
            address(token0),
            address(token1),
            0,
            ZERO_ADDRESS,
            new bytes(0)
        );

        assertEq(swapFeeModuleData.feeInBips, feeInBips);

        // for token1
        feeInBips =
            solverWriteSlot.feeMinToken1 +
            uint32(
                Math.mulDiv(
                    solverWriteSlot.feeGrowthE6Token1,
                    (block.timestamp - solverWriteSlot.lastProcessedSignatureTimestamp),
                    100
                )
            );

        if (feeInBips > solverWriteSlot.feeMaxToken1) {
            feeInBips = solverWriteSlot.feeMaxToken1;
        }

        vm.prank(address(pool));
        swapFeeModuleData = sot.getSwapFeeInBips(address(token1), address(token0), 0, ZERO_ADDRESS, new bytes(0));

        assertEq(swapFeeModuleData.feeInBips, feeInBips);

        vm.revertTo(snapshot);

        vm.warp(block.timestamp + 10000);

        // for token0
        feeInBips =
            solverWriteSlot.feeMinToken0 +
            uint32(
                Math.mulDiv(
                    solverWriteSlot.feeGrowthE6Token0,
                    (block.timestamp - solverWriteSlot.lastProcessedSignatureTimestamp),
                    100
                )
            );

        if (feeInBips > solverWriteSlot.feeMaxToken0) {
            feeInBips = solverWriteSlot.feeMaxToken0;
        }

        vm.prank(address(pool));

        swapFeeModuleData = sot.getSwapFeeInBips(address(token0), address(token1), 0, ZERO_ADDRESS, new bytes(0));

        assertEq(swapFeeModuleData.feeInBips, feeInBips);

        // for token1
        feeInBips =
            solverWriteSlot.feeMinToken1 +
            uint32(
                Math.mulDiv(
                    solverWriteSlot.feeGrowthE6Token1,
                    (block.timestamp - solverWriteSlot.lastProcessedSignatureTimestamp),
                    100
                )
            );

        if (feeInBips > solverWriteSlot.feeMaxToken1) {
            feeInBips = solverWriteSlot.feeMaxToken1;
        }

        vm.prank(address(pool));
        swapFeeModuleData = sot.getSwapFeeInBips(address(token1), address(token0), 0, ZERO_ADDRESS, new bytes(0));

        assertEq(swapFeeModuleData.feeInBips, feeInBips);
    }

    function test_getSwapFeeInBips_solverSwap() public {
        SolverReadSlot memory solverReadSlot = getSolverReadSlot();

        solverReadSlot.maxAllowedQuotes = 5;
        solverReadSlot.solverFeeBipsToken0 = 10;
        solverReadSlot.solverFeeBipsToken1 = 20;

        _setSolverReadSlot(solverReadSlot);

        vm.prank(address(pool));
        SwapFeeModuleData memory swapFeeModuleData = sot.getSwapFeeInBips(
            address(token0),
            address(token1),
            0,
            ZERO_ADDRESS,
            new bytes(1)
        );

        assertEq(swapFeeModuleData.feeInBips, 10);

        vm.prank(address(pool));
        swapFeeModuleData = sot.getSwapFeeInBips(ZERO_ADDRESS, ZERO_ADDRESS, 0, ZERO_ADDRESS, new bytes(1));

        assertEq(swapFeeModuleData.feeInBips, 20);
    }

    function test_poolNonReentrant() public {
        vm.store(address(pool), bytes32(uint256(0)), bytes32(uint256(2)));

        assertEq(pool.isLocked(), true, 'Pool Not Locked');

        vm.expectRevert(SOT.SOT__poolReentrant.selector);
        sot.effectiveAMMLiquidity();

        vm.expectRevert(SOT.SOT__poolReentrant.selector);
        sot.getAMMState();

        vm.expectRevert(SOT.SOT__poolReentrant.selector);
        sot.getReservesAtPrice(0);

        vm.expectRevert(SOT.SOT__poolReentrant.selector);
        sot.setPriceBounds(0, 0, 0, 0);
    }

    function test_eip712Signature() public {
        address publicKey = 0xA52A878CE46F233794FeE5c976eb2528e17510d7;
        uint256 privateKey = 0x709fd5c6a885a6efbe01bce2d72cb1b4b0c56abcf3599f39108764ce5bf2c59e;
        address sotAddress = 0xf678F3DF67EBea04b3a0c1C2636eEc2504c92BA2;

        SolverOrderType memory sotParams = SolverOrderType({
            amountInMax: 10e18,
            sqrtSolverPriceX96Discounted: getSqrtPriceX96(
                2290 * (10 ** feedToken0.decimals()),
                1 * (10 ** feedToken1.decimals())
            ),
            // Solving is expensive and we don't want to SOT reverts
            // multiple SOT can land in the same block
            // the first SOT is doing the favor of unlocking the pool, shifting the spotPrice
            // if you land first you'll get the discounted price if you land second you will get a base price
            sqrtSolverPriceX96Base: getSqrtPriceX96(
                2290 * (10 ** feedToken0.decimals()),
                1 * (10 ** feedToken1.decimals())
            ),
            // new AMM spot price after the swap
            sqrtSpotPriceX96New: 3791986971626720137260477456763,
            authorizedRecipient: publicKey,
            authorizedSender: publicKey,
            // should be a current block timestamp
            signatureTimestamp: 0,
            expiry: 1000,
            // soft lock of AMM, in block0 the price is 100 and we know the price would be 98 < > 102
            feeMinToken0: 10, // 10 = 0.01%
            feeMaxToken0: 100, // 100 = 1%
            feeGrowthE6Token0: 500, // 0 %% 10*4
            feeMinToken1: 10,
            feeMaxToken1: 100,
            feeGrowthE6Token1: 500,
            // every time alternate the expected flag between 0 and 1
            nonce: 24,
            expectedFlag: 1,
            isZeroToOne: false
        });

        bytes32 digest = keccak256(
            abi.encodePacked(
                '\x19\x01',
                getDomainSeparatorV4(11155111, sotAddress),
                keccak256(abi.encode(SOTConstants.SOT_TYPEHASH, sotParams))
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

        bytes memory signature = abi.encodePacked(r, s, bytes1(v));

        bytes
            memory viemSignature = hex'982d655882b1f267e7692341df9edce4f4b9c1ce626d36dc5cd27725e1d40b9f67f4c3d6e8d356fe03112c9d9be9af0d983e7f19248f16e9573d1407f004bc191b';

        assertEq(signature, viemSignature, 'eip712 signature mismatch');

        emit LogBytes(signature);
    }

    function test_setFeeds() public {
        SovereignPoolConstructorArgs memory poolArgs = _generateDefaultConstructorArgs();
        pool = this.deploySovereignPool(poolArgs);
        SOTConstructorArgs memory sotArgs = generateDefaultSOTConstructorArgs(pool);
        sotArgs.feedToken0 = address(0);
        sotArgs.feedToken1 = address(0);

        sot = this.deploySOT(sotArgs);

        vm.startPrank(makeAddr('NOT_MANAGER'));
        vm.expectRevert(SOT.SOT__onlyManager.selector);
        sot.setFeeds(address(1), address(1));
        vm.stopPrank();

        vm.expectRevert(SOT.SOT__setFeeds_feedSetNotApproved.selector);
        sot.setFeeds(address(1), address(1));

        vm.startPrank(makeAddr('NOT_LIQUIDITY_PROVIDER'));
        vm.expectRevert(SOT.SOT__onlyLiquidityProvider.selector);
        sot.approveFeedSet();
        vm.stopPrank();

        sot.approveFeedSet();
        sot.setFeeds(address(1), address(1));

        assertEq(address(sot.feedToken0()), address(1), 'feedToken0');
        assertEq(address(sot.feedToken1()), address(1), 'feedToken1');

        vm.expectRevert(SOTOracle.SOTOracle___setFeeds_feedsAlreadySet.selector);
        sot.setFeeds(address(2), address(2));
    }

    function test_setAMMFees() public {
        SolverWriteSlot memory expectedSolverWriteSlot = getSolverWriteSlot();

        vm.startPrank(makeAddr('NOT_LIQUIDITY_PROVIDER'));
        vm.expectRevert(SOT.SOT__onlyLiquidityProvider.selector);
        sot.setAMMFees(100, 200, 300, 400, 500, 600);
        vm.stopPrank();

        sot.setAMMFees(100, 200, 300, 400, 500, 600);

        SolverWriteSlot memory solverWriteSlot = getSolverWriteSlot();

        expectedSolverWriteSlot.feeMinToken0 = 100;
        expectedSolverWriteSlot.feeMaxToken0 = 200;
        expectedSolverWriteSlot.feeGrowthE6Token0 = 300;
        expectedSolverWriteSlot.feeMinToken1 = 400;
        expectedSolverWriteSlot.feeMaxToken1 = 500;
        expectedSolverWriteSlot.feeGrowthE6Token1 = 600;

        checkSolverWriteSlot(solverWriteSlot, expectedSolverWriteSlot);
    }

    function test_swap_zeroAmount() public {
        SovereignPoolSwapContextData memory data;
        SovereignPoolSwapParams memory params = SovereignPoolSwapParams({
            isSwapCallback: false,
            isZeroToOne: false,
            amountIn: 1,
            amountOutMin: 0,
            recipient: address(this),
            deadline: block.timestamp + 2,
            swapTokenOut: address(token0),
            swapContext: data
        });

        vm.expectRevert(SOT.SOT__getLiquidityQuote_zeroAmountOut.selector);
        pool.swap(params);
    }
}
