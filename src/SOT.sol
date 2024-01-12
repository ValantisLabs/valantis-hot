// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { LiquidityAmounts } from '@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol';
import { SwapMath } from '@uniswap/v3-core/contracts/libraries/SwapMath.sol';

import { IERC20 } from 'valantis-core/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import { SafeERC20 } from 'valantis-core/lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol';
import { EIP712 } from 'valantis-core/lib/openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol';
import { Math } from 'valantis-core/lib/openzeppelin-contracts/contracts/utils/math/Math.sol';
import { SafeCast } from 'valantis-core/lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol';
import {
    SignatureChecker
} from 'valantis-core/lib/openzeppelin-contracts/contracts/utils/cryptography/SignatureChecker.sol';
import { ReentrancyGuard } from 'valantis-core/lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol';
import {
    ISovereignALM,
    ALMLiquidityQuote,
    ALMLiquidityQuoteInput
} from 'valantis-core/src/alm/interfaces/ISovereignALM.sol';
import { ISovereignPool } from 'valantis-core/src/pools/interfaces/ISovereignPool.sol';
import { ISwapFeeModule, SwapFeeModuleData } from 'valantis-core/src/swap-fee-modules/interfaces/ISwapFeeModule.sol';

import { SOTParams } from 'src/libraries/SOTParams.sol';
import { TightPack } from 'src/libraries/utils/TightPack.sol';
import { AlternatingNonceBitmap } from 'src/libraries/AlternatingNonceBitmap.sol';
import { SOTConstants } from 'src/libraries/SOTConstants.sol';
import { SolverOrderType, SwapState } from 'src/structs/SOTStructs.sol';
import { SOTOracle } from 'src/SOTOracle.sol';

/**
    @title Solver Order Type.
    @notice Valantis Sovereign Liquidity Module.
    // TODO: Remove unnecessary reentrancy guards if any
 */
contract SOT is ISovereignALM, ISwapFeeModule, EIP712, ReentrancyGuard, SOTOracle {
    using Math for uint256;
    using SafeCast for uint256;
    using SignatureChecker for address;
    using SOTParams for SolverOrderType;
    using SafeERC20 for IERC20;
    using TightPack for TightPack.PackedState;
    using AlternatingNonceBitmap for uint64;

    /************************************************
     *  CUSTOM ERRORS
     ***********************************************/

    error SOT__onlyPool();
    error SOT__onlyManager();
    error SOT__onlyLiquidityProvider();
    error SOT__constructor_invalidLiquidityProvider();
    error SOT__constructor_invalidMinAmmFee();
    error SOT__constructor_invalidMaxAmmFeeGrowth();
    error SOT__constructor_invalidMinAmmFeeGrowth();
    error SOT__constructor_invalidMaxDelay();
    error SOT__constructor_invalidOracleMaxDiff();
    error SOT__constructor_invalidSolverDiscount();
    error SOT__constructor_invalidSovereignPool();
    error SOT__constructor_invalidToken0();
    error SOT__constructor_invalidToken1();
    error SOT__getLiquidityQuote_invalidFeePath();
    error SOT__getLiquidityQuote_invalidSignature();
    error SOT__getLiquidityQuote_maxSolverQuotesExceeded();
    error SOT__setPriceBounds_invalidPriceBounds();
    error SOT__setPriceBounds_invalidSqrtSpotPriceX96(uint160 sqrtSpotPriceX96);
    error SOT__setSolverFeeInBips_invalidSolverFee();

    /************************************************
     *  IMMUTABLES
     ***********************************************/

    /**
	    @notice Sovereign Pool to which this Liquidity Module is bound.
    */
    address public immutable pool;

    /**
	    @notice Address of account which is meant to deposit & withdraw liquidity.
     */
    address public immutable liquidityProvider;

    /**
	    @notice Maximum delay, in seconds, for acceptance of SOT quotes.
    */
    uint32 public immutable maxDelay;

    /**
	    @notice Maximum price discount allowed for SOT quotes,
                expressed in basis-points.
    */
    uint16 public immutable solverMaxDiscountBips;

    /**
	    @notice Maximum allowed relative deviation
                between spot price and oracle price,
                expressed in basis-points.
     */
    uint16 public immutable oraclePriceMaxDiffBips;

    /**
	    @notice Bounds the growth rate, in basis-points, of the AMM fee 
					as time increases between last processed quote.
        @dev SOT reverts if feeGrowth exceeds these bounds.
     */
    uint16 public immutable minAmmFeeGrowth;
    uint16 public immutable maxAmmFeeGrowth;

    /**
	    @notice Minimum allowed AMM fee, in basis-points.
	    @dev SOT reverts if feeMin is below this value.
     */
    uint16 public immutable minAmmFee;

    /************************************************
     *  STORAGE
     ***********************************************/

    /**
		@notice Account that manages all access controls to this liquidity module.
     */
    address public manager;

    /**
	    @notice Address of account which is meant to validate SOT quote signatures.
        @dev Can be updated by `manager`.
     */
    address public signer;

    /**
	    @notice Maximum amount of token{0,1} to quote to solvers on each SOT.
        @dev Can be updated by `manager`.
	    @dev Since there can only be one SOT per block, this is also a maximum
             allowed SOT quote volume per block.
     */
    uint256 public maxToken0VolumeToQuote;
    uint256 public maxToken1VolumeToQuote;

    /**
        @notice Tight packed storage slots for - 
            * sqrtSpotPriceX96 (a): AMM square-root spot price, in Q64.96 format.
            * sqrtPriceLowX96 (b): square-root lower price bound, in Q64.96 format.
            * sqrtPriceHighX96 (c): square-root upper price bound, in Q64.96 format.
        
        @dev sqrtSpotPriceX96, sqrtPriceLowX96, and sqrtPriceHighX96 values are packed into 2 slots.
            *slot1:
                <<  32 free bits | upper 64 bits of sqrtPriceLowX96 | 160 bits of sqrtSpotPriceX96 >>
            *slot2:
                << lower 96 bits  of sqrtPriceLowX96 | 160 bits of sqrtPriceHighX96 >>
 

        @dev sqrtSpotPriceX96 can only be updated on AMM swaps or after processing a valid SOT quote.
     */
    TightPack.PackedState public ammState;

    /**
        @notice Contains state variables which get updated on swaps. 
     */
    SwapState public swapState;

    /************************************************
     *  MODIFIERS
     ***********************************************/

    modifier onlyPool() {
        if (msg.sender != pool) {
            revert SOT__onlyPool();
        }
        _;
    }

    modifier onlyManager() {
        if (msg.sender != manager) {
            revert SOT__onlyManager();
        }
        _;
    }

    modifier onlyLiquidityProvider() {
        if (msg.sender != liquidityProvider) {
            revert SOT__onlyLiquidityProvider();
        }
        _;
    }

    /**
        @notice Checks that the current AMM spot price is within the expected range.
        @param _expectedSqrtSpotPriceUpperX96 Upper limit for expected spot price.
        @param _expectedSqrtSpotPriceLowerX96 Lower limit for expected spot price.
        @dev if both _expectedSqrtSpotPriceUpperX96 and _expectedSqrtSpotPriceLowerX96 are 0,
             then no check is performed.
        @dev this modifier is used to prevent price manipulation attacks against critical liquidity functions

     */
    modifier onlySpotPriceRange(uint160 _expectedSqrtSpotPriceUpperX96, uint160 _expectedSqrtSpotPriceLowerX96) {
        if (_expectedSqrtSpotPriceUpperX96 + _expectedSqrtSpotPriceLowerX96 != 0) {
            uint160 sqrtSpotPriceX96 = ammState.getA();

            // Check that spot price has not been manipulated before updating price bounds
            if (
                sqrtSpotPriceX96 > _expectedSqrtSpotPriceUpperX96 || sqrtSpotPriceX96 < _expectedSqrtSpotPriceLowerX96
            ) {
                revert SOT__setPriceBounds_invalidSqrtSpotPriceX96(sqrtSpotPriceX96);
            }
        }

        _;
    }

    /************************************************
     *  CONSTRUCTOR
     ***********************************************/

    constructor(
        address _pool,
        address _liquidityProvider,
        uint32 _maxDelay,
        uint16 _solverMaxDiscountBips,
        uint16 _oraclePriceMaxDiffBips,
        uint32 _maxOracleUpdateDuration,
        uint16 _minAmmFeeGrowth,
        uint16 _maxAmmFeeGrowth,
        uint16 _minAmmFee,
        address _feedToken0,
        address _feedToken1
    )
        EIP712('Valantis Solver Order Type', '1')
        SOTOracle(
            ISovereignPool(_pool).token0(),
            ISovereignPool(_pool).token1(),
            _feedToken0,
            _feedToken1,
            _maxOracleUpdateDuration
        )
    {
        if (_pool == address(0)) {
            revert SOT__constructor_invalidSovereignPool();
        }

        pool = _pool;

        if (_liquidityProvider == address(0)) {
            revert SOT__constructor_invalidLiquidityProvider();
        }

        liquidityProvider = _liquidityProvider;

        if (_maxDelay > SOTConstants.MAX_DELAY_ALLOWED) {
            revert SOT__constructor_invalidMaxDelay();
        }

        maxDelay = _maxDelay;

        if (_solverMaxDiscountBips > SOTConstants.SOLVER_MAX_DISCOUNT) {
            revert SOT__constructor_invalidSolverDiscount();
        }

        solverMaxDiscountBips = _solverMaxDiscountBips;

        if (_oraclePriceMaxDiffBips > SOTConstants.MAX_ORACLE_PRICE_DIFF) {
            revert SOT__constructor_invalidOracleMaxDiff();
        }

        oraclePriceMaxDiffBips = _oraclePriceMaxDiffBips;

        if (_minAmmFeeGrowth > SOTConstants.BIPS) {
            revert SOT__constructor_invalidMinAmmFeeGrowth();
        }

        minAmmFeeGrowth = _minAmmFeeGrowth;

        if (_maxAmmFeeGrowth > SOTConstants.BIPS) {
            revert SOT__constructor_invalidMaxAmmFeeGrowth();
        }

        maxAmmFeeGrowth = _maxAmmFeeGrowth;

        if (_minAmmFee > SOTConstants.BIPS) {
            revert SOT__constructor_invalidMinAmmFee();
        }

        minAmmFee = _minAmmFee;
    }

    /************************************************
     *  GETTER FUNCTIONS
     ***********************************************/

    /**
        @notice Returns the AMM reserves assuming some AMM spot price
        @dev this is a temporary implementation of the function.
        // TODO: add correct reserves calculation.
     */
    function getReservesAtPrice(uint160) external view returns (uint256 reserve0, uint256 reserve1) {
        (reserve0, reserve1) = ISovereignPool(pool).getReserves();
    }

    /************************************************
     *  SETTER FUNCTIONS
     ***********************************************/

    /**
        @notice Changes the manager of the pool ( To be protected by timelock )
     */
    function setManager(address _manager) external onlyManager {
        manager = _manager;
    }

    /**
        @notice Changes the signer of the pool ( To be protected by timelock )
     */
    function setSigner(address _signer) external onlyManager {
        signer = _signer;
    }

    /**
        @notice Changes the maximum token volumes available for a single SOT quote ( To be protected by timelock )
     */
    function setMaxTokenVolumes(uint256 _maxToken0VolumeToQuote, uint256 _maxToken1VolumeToQuote) external onlyManager {
        maxToken0VolumeToQuote = _maxToken0VolumeToQuote;
        maxToken1VolumeToQuote = _maxToken1VolumeToQuote;
    }

    /**
        @notice Changes the standard fee charged on all solver swaps ( To be protected by timelock )
     */
    function setSolverFeeInBips(uint16 _solverFeeInBips) external onlyManager {
        if (_solverFeeInBips > SOTConstants.MAX_SOLVER_FEE_IN_BIPS) {
            revert SOT__setSolverFeeInBips_invalidSolverFee();
        }

        swapState.solverFeeInBips = _solverFeeInBips;
    }

    /**
        @notice Sets the AMM position's square-root upper and lower prince bounds
        @param _sqrtPriceLowX96 New square-root lower price bound
        @param _sqrtPriceHighX96 New square-root upper price bound
        @param _expectedSqrtSpotPriceUpperX96 Upper limit for expected spot price when setting new bounds
        @param _expectedSqrtSpotPriceLowerX96 Lower limit for expected spot price when setting new bounds
        @dev Can be used to utilize disproportionate token liquidity by tuning price bounds offchain
     */
    function setPriceBounds(
        uint128 _sqrtPriceLowX96,
        uint128 _sqrtPriceHighX96,
        uint160 _expectedSqrtSpotPriceUpperX96,
        uint160 _expectedSqrtSpotPriceLowerX96
    )
        external
        onlyLiquidityProvider
        onlySpotPriceRange(_expectedSqrtSpotPriceUpperX96, _expectedSqrtSpotPriceLowerX96)
    {
        // Check that lower bound is smaller than upper bound, and both are not 0
        if (_sqrtPriceLowX96 >= _sqrtPriceHighX96 || _sqrtPriceLowX96 == 0) {
            revert SOT__setPriceBounds_invalidPriceBounds();
        }

        // Check that the price bounds are within the MAX and MIN sqrt prices
        if (_sqrtPriceLowX96 < SOTConstants.MIN_SQRT_PRICE || _sqrtPriceHighX96 > SOTConstants.MAX_SQRT_PRICE) {
            revert SOT__setPriceBounds_invalidPriceBounds();
        }

        ammState.setState(ammState.getA(), _sqrtPriceLowX96, _sqrtPriceHighX96);
    }

    /************************************************
     *  EXTERNAL FUNCTIONS
     ***********************************************/

    function getLiquidityQuote(
        ALMLiquidityQuoteInput memory _almLiquidityQuoteInput,
        bytes calldata _externalContext,
        bytes calldata /*_verifierData*/
    ) external override onlyPool returns (ALMLiquidityQuote memory liquidityQuote) {
        if (_externalContext.length == 0) {
            // AMM Swap
            _ammSwap(_almLiquidityQuoteInput, liquidityQuote);
        } else {
            // Solver Swap
            _solverSwap(_almLiquidityQuoteInput, _externalContext, liquidityQuote);
        }
    }

    function depositLiquidity(
        uint256 _amount0,
        uint256 _amount1,
        uint160 _expectedSqrtSpotPriceUpperX96,
        uint160 _expectedSqrtSpotPriceLowerX96
    )
        external
        onlyLiquidityProvider
        onlySpotPriceRange(_expectedSqrtSpotPriceUpperX96, _expectedSqrtSpotPriceLowerX96)
        nonReentrant
    {
        ISovereignPool(pool).depositLiquidity(_amount0, _amount1, liquidityProvider, '', '');
    }

    function withdrawLiquidity(
        uint256 _amount0,
        uint256 _amount1,
        uint160 _expectedSqrtSpotPriceUpperX96,
        uint160 _expectedSqrtSpotPriceLowerX96
    )
        external
        onlyLiquidityProvider
        onlySpotPriceRange(_expectedSqrtSpotPriceUpperX96, _expectedSqrtSpotPriceLowerX96)
        nonReentrant
    {
        ISovereignPool(pool).withdrawLiquidity(_amount0, _amount1, liquidityProvider, liquidityProvider, '');
    }

    function getSwapFeeInBips(
        bool /**_isZeroToOne*/,
        uint256 /**_amountIn*/,
        address /**_user*/,
        bytes memory _swapFeeModuleContext
    ) external view returns (SwapFeeModuleData memory swapFeeModuleData) {
        if (_swapFeeModuleContext.length != 0) {
            // Solver Branch
            // Solver Branch is verified during the getLiquidityQuote call
            swapFeeModuleData.feeInBips = swapState.solverFeeInBips;
        } else {
            swapFeeModuleData.feeInBips = _getAMMFee();
        }
    }

    function callbackOnSwapEnd(
        uint256 /*_effectiveFee*/,
        int24 /*_spotPriceTick*/,
        uint256 /*_amountInUsed*/,
        uint256 /*_amountOut*/,
        SwapFeeModuleData memory /*_swapFeeModuleData*/
    ) external {
        // Fee Module callback for Universal Pool ( not needed here)
    }

    function callbackOnSwapEnd(
        uint256 /*_effectiveFee*/,
        uint256 /*_amountInUsed*/,
        uint256 /*_amountOut*/,
        SwapFeeModuleData memory /*_swapFeeModuleData*/
    ) external {
        // Fee Module callback for Sovereign Pool ( not needed here)
    }

    function onDepositLiquidityCallback(
        uint256 _amount0,
        uint256 _amount1,
        bytes memory /*_data*/
    ) external override onlyPool {
        if (_amount0 > 0) {
            IERC20(ISovereignPool(pool).token0()).safeTransferFrom(liquidityProvider, msg.sender, _amount0);
        }

        if (_amount1 > 0) {
            IERC20(ISovereignPool(pool).token1()).safeTransferFrom(liquidityProvider, msg.sender, _amount1);
        }
    }

    function onSwapCallback(
        bool /*_isZeroToOne*/,
        uint256 /*_amountIn*/,
        uint256 /*_amountOut*/
    ) external override onlyPool {
        // Liquidity QUote callback by Sovereign Pool ( not needed here)
    }

    /************************************************
     *  INTERNAL FUNCTIONS
     ***********************************************/

    function _getAMMFee() private view returns (uint32 feeInBips) {
        // TODO: Test if all the calculations are in bips.
        // TODO: Add some min and max bounds to AMM fee.
        SwapState memory swapStateCache = swapState;

        feeInBips =
            uint32(swapStateCache.lastProcessedFeeGrowth) *
            uint32(block.timestamp - swapStateCache.lastProcessedSignatureTimestamp);
        // Add minimum fee
        feeInBips += uint32(swapStateCache.lastProcessedFeeMin);
        // Cap fee if necessary
        if (feeInBips > uint32(swapStateCache.lastProcessedFeeMax)) {
            feeInBips = uint32(swapStateCache.lastProcessedFeeMax);
        }
    }

    function _getEffectiveLiquidity(
        uint160 sqrtRatioX96Cache,
        uint160 sqrtRatioAX96Cache,
        uint160 sqrtRatioBX96Cache
    ) private view returns (uint128 effectiveLiquidity) {
        // Query current reserves
        // This already excludes poolManager and protocol fees
        (uint256 reserve0, uint256 reserve1) = ISovereignPool(pool).getReserves();

        uint128 liquidity0 = LiquidityAmounts.getLiquidityForAmount0(sqrtRatioX96Cache, sqrtRatioBX96Cache, reserve0);
        uint128 liquidity1 = LiquidityAmounts.getLiquidityForAmount1(sqrtRatioAX96Cache, sqrtRatioX96Cache, reserve1);

        if (liquidity0 < liquidity1) {
            effectiveLiquidity = liquidity0;
        } else {
            effectiveLiquidity = liquidity1;
        }
    }

    function _ammSwap(
        ALMLiquidityQuoteInput memory almLiquidityQuoteInput,
        ALMLiquidityQuote memory liquidityQuote
    ) internal {
        // Check that the fee path was chosen correctly
        if (almLiquidityQuoteInput.feeInBips != _getAMMFee()) {
            revert SOT__getLiquidityQuote_invalidFeePath();
        }

        // Cache sqrt spot price, lower bound, and upper bound
        (uint160 sqrtPriceX96Cache, uint160 sqrtPriceLowX96Cache, uint160 sqrtPriceHighX96Cache) = ammState
            .unpackState();

        // Calculate liquidity available to be utilized in this swap
        uint128 effectiveLiquidity = _getEffectiveLiquidity(
            sqrtPriceX96Cache,
            sqrtPriceLowX96Cache,
            sqrtPriceHighX96Cache
        );

        uint160 sqrtSpotPriceX96New;

        // Calculate amountOut according to CPMM math
        if (almLiquidityQuoteInput.isZeroToOne) {
            (sqrtSpotPriceX96New, liquidityQuote.amountInFilled, liquidityQuote.amountOut, ) = SwapMath.computeSwapStep(
                sqrtPriceX96Cache,
                sqrtPriceLowX96Cache,
                effectiveLiquidity,
                almLiquidityQuoteInput.amountInMinusFee.toInt256(), // always exact input swap
                0
            ); // fees have already been deducted
        } else {
            (sqrtSpotPriceX96New, liquidityQuote.amountInFilled, liquidityQuote.amountOut, ) = SwapMath.computeSwapStep(
                sqrtPriceX96Cache,
                sqrtPriceHighX96Cache,
                effectiveLiquidity,
                almLiquidityQuoteInput.amountInMinusFee.toInt256(), // always exact input swap
                0
            ); // fees have already been deducted
        }

        // Reserves are always kept in Sovereign Pool
        liquidityQuote.quoteFromPoolReserves = true;

        ammState.setA(sqrtSpotPriceX96New);
    }

    function _solverSwap(
        ALMLiquidityQuoteInput memory almLiquidityQuoteInput,
        bytes memory externalContext,
        ALMLiquidityQuote memory liquidityQuote
    ) internal {
        (SolverOrderType memory sot, bytes memory signature) = abi.decode(externalContext, (SolverOrderType, bytes));

        // Execute SOT swap
        SwapState memory swapStateCache = swapState;

        // Check that the fee path was chosen correctly
        if (almLiquidityQuoteInput.feeInBips != swapStateCache.solverFeeInBips) {
            revert SOT__getLiquidityQuote_invalidFeePath();
        }

        // A solver only updates state if -
        // 1. It is the first solver quote in the block
        // 2. It was signed after the last processed signature timestamp
        bool isDiscountedSolver = (swapStateCache.lastProcessedBlockTimestamp < block.timestamp) &&
            (swapStateCache.lastProcessedSignatureTimestamp < sot.signatureTimestamp);

        uint256 solverPriceX192 = isDiscountedSolver ? sot.solverPriceX192Discounted : sot.solverPriceX192Base;

        // Always true, since reserves must be stored in the pool
        liquidityQuote.quoteFromPoolReserves = true;
        // Calculate the amountOut according to the quoted price
        liquidityQuote.amountOut = almLiquidityQuoteInput.isZeroToOne
            ? Math.mulDiv(almLiquidityQuoteInput.amountInMinusFee, solverPriceX192, SOTConstants.Q192)
            : Math.mulDiv(almLiquidityQuoteInput.amountInMinusFee, SOTConstants.Q192, solverPriceX192);
        liquidityQuote.amountInFilled = almLiquidityQuoteInput.amountInMinusFee;

        sot.validateFeeParams(minAmmFee, minAmmFeeGrowth, maxAmmFeeGrowth);

        sot.validateBasicParams(
            liquidityQuote.amountOut,
            almLiquidityQuoteInput.recipient,
            almLiquidityQuoteInput.amountInMinusFee,
            almLiquidityQuoteInput.isZeroToOne ? maxToken1VolumeToQuote : maxToken0VolumeToQuote,
            maxDelay,
            swapStateCache.alternatingNonceBitmap
        );

        SOTParams.validatePriceBounds(
            ammState,
            solverPriceX192.sqrt().toUint160(),
            sot.sqrtSpotPriceX96New,
            getSqrtOraclePriceX96(),
            oraclePriceMaxDiffBips,
            solverMaxDiscountBips
        );

        bytes32 sotHash = sot.hashParams();

        if (!signer.isValidSignatureNow(_hashTypedDataV4(sotHash), signature)) {
            revert SOT__getLiquidityQuote_invalidSignature();
        }

        // Only update the pool state, if this is a discounted solver quote
        if (isDiscountedSolver) {
            swapState = SwapState({
                lastProcessedBlockTimestamp: (block.timestamp).toUint32(),
                lastProcessedSignatureTimestamp: sot.signatureTimestamp,
                lastProcessedFeeGrowth: sot.feeGrowth,
                lastProcessedFeeMin: sot.feeMin,
                lastProcessedFeeMax: sot.feeMax,
                solverFeeInBips: swapStateCache.solverFeeInBips,
                lastProcessedBlockQuoteCount: 1,
                alternatingNonceBitmap: swapStateCache.alternatingNonceBitmap.flipNonce(sot.nonce)
            });

            ammState.setA(sot.sqrtSpotPriceX96New);
        } else {
            if (swapStateCache.lastProcessedBlockQuoteCount + 1 > SOTConstants.MAX_SOT_QUOTES_IN_BLOCK) {
                revert SOT__getLiquidityQuote_maxSolverQuotesExceeded();
            }
            swapState.lastProcessedBlockQuoteCount = swapStateCache.lastProcessedBlockQuoteCount + 1;
        }
    }
}
