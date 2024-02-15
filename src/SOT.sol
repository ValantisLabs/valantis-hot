// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { console } from 'forge-std/console.sol';

import { SwapMath } from '@uniswap/v3-core/contracts/libraries/SwapMath.sol';

import { IERC20 } from 'valantis-core/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import { SafeERC20 } from 'valantis-core/lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol';
import { EIP712 } from 'valantis-core/lib/openzeppelin-contracts/contracts/utils/cryptography/EIP712.sol';
import { Math } from 'valantis-core/lib/openzeppelin-contracts/contracts/utils/math/Math.sol';
import { SafeCast } from 'valantis-core/lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol';
import {
    SignatureChecker
} from 'valantis-core/lib/openzeppelin-contracts/contracts/utils/cryptography/SignatureChecker.sol';
import {
    ISovereignALM,
    ALMLiquidityQuote,
    ALMLiquidityQuoteInput
} from 'valantis-core/src/alm/interfaces/ISovereignALM.sol';
import { ISovereignPool } from 'valantis-core/src/pools/interfaces/ISovereignPool.sol';
import { ISwapFeeModule, SwapFeeModuleData } from 'valantis-core/src/swap-fee-modules/interfaces/ISwapFeeModule.sol';

import { SOTParams } from 'src/libraries/SOTParams.sol';
import { TightPack } from 'src/libraries/utils/TightPack.sol';
import { LiquidityAmounts } from 'src/libraries/LiquidityAmounts.sol';
import { AlternatingNonceBitmap } from 'src/libraries/AlternatingNonceBitmap.sol';
import { SOTConstants } from 'src/libraries/SOTConstants.sol';
import {
    SolverOrderType,
    SolverWriteSlot,
    SolverReadSlot,
    SOTConstructorArgs,
    AMMState
} from 'src/structs/SOTStructs.sol';
import { SOTOracle } from 'src/SOTOracle.sol';

/**
    @title Solver Order Type.
    @notice Valantis Sovereign Liquidity Module.
    TODO: Remove unnecessary reentrancy guards if any
    TODO: Add checks for state of Sovereign Pool like - 
            * feeModule should be set to SOT
            * no sovereign vault/ no verifier module/
            * both tokens are as expected
            * state of rebase tokens
            * alm is set correctly
 */
contract SOT is ISovereignALM, ISwapFeeModule, EIP712, SOTOracle {
    using Math for uint256;
    using SafeCast for uint256;
    using SignatureChecker for address;
    using SOTParams for SolverOrderType;
    using SafeERC20 for IERC20;
    using TightPack for AMMState;
    using AlternatingNonceBitmap for uint56;

    /************************************************
     *  CUSTOM ERRORS
     ***********************************************/

    error SOT__onlyPool();
    error SOT__onlyManager();
    error SOT__onlyLiquidityProvider();
    error SOT__onlyUnpaused();
    error SOT__reentrant();
    error SOT__constructor_invalidFeeGrowthBounds();
    error SOT__constructor_invalidLiquidityProvider();
    error SOT__constructor_invalidMinAmmFee();
    error SOT__constructor_invalidManager();
    error SOT__constructor_invalidOraclePriceMaxDiffBips();
    error SOT__constructor_invalidSigner();
    error SOT__constructor_invalidSolverMaxDiscountBips();
    error SOT__constructor_invalidSovereignPool();
    error SOT__constructor_invalidToken0();
    error SOT__constructor_invalidToken1();
    error SOT__getLiquidityQuote_invalidFeePath();
    error SOT__getLiquidityQuote_invalidSignature();
    error SOT__getLiquidityQuote_maxSolverQuotesExceeded();
    error SOT__setMaxAllowedQuotes_invalidMaxAllowedQuotes();
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
        Min Value: 0 %
        Max Value: 0.65535 % per second
        @dev SOT reverts if feeGrowthInPips exceeds these bounds.

     */
    uint16 public immutable minAmmFeeGrowthInPips;
    uint16 public immutable maxAmmFeeGrowthInPips;

    /**
	    @notice Minimum allowed AMM fee, in basis-points.
	    @dev SOT reverts if feeMin is below this value.
     */
    uint16 public immutable minAmmFee;

    /************************************************
     *  STORAGE
     ***********************************************/

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
    AMMState private _ammState;

    /**
        @notice Contains state variables which get updated on swaps. 
     */
    SolverWriteSlot public solverWriteSlot;

    /**
	    @notice Address of account which is meant to validate SOT quote signatures.
        @dev Can be updated by `manager`.
     */
    SolverReadSlot public solverReadSlot;

    /**
		@notice Account that manages all access controls to this liquidity module.
     */
    address public manager;

    /**
	    @notice Maximum amount of token{0,1} to quote to solvers on each SOT.
        @dev Can be updated by `manager`.
	    @dev Since there can only be one SOT per block, this is also a maximum
             allowed SOT quote volume per block.
     */
    uint256 public maxToken0VolumeToQuote;
    uint256 public maxToken1VolumeToQuote;

    /************************************************
     *  MODIFIERS
     ***********************************************/

    modifier onlyPool() {
        _onlyPool();
        _;
    }

    modifier onlyManager() {
        _onlyManager();
        _;
    }

    modifier onlyLiquidityProvider() {
        _onlyLiquidityProvider();
        _;
    }

    modifier onlyUnpaused() {
        _onlyUnpaused();
        _;
    }

    modifier nonReentrant() {
        // 1st bit of flags: ReentrancyLock
        if (_ammState.getFlag(SOTConstants.REENTRANCY_FLAG)) {
            revert SOT__reentrant();
        }
        _ammState.setFlag(SOTConstants.REENTRANCY_FLAG, true);
        _;

        _ammState.setFlag(SOTConstants.REENTRANCY_FLAG, false);
    }

    /************************************************
     *  CONSTRUCTOR
     ***********************************************/

    constructor(
        SOTConstructorArgs memory _args
    )
        EIP712('Valantis Solver Order Type', '1')
        SOTOracle(
            ISovereignPool(_args.pool).token0(),
            ISovereignPool(_args.pool).token1(),
            _args.feedToken0,
            _args.feedToken1,
            _args.maxOracleUpdateDurationFeed0,
            _args.maxOracleUpdateDurationFeed1
        )
    {
        if (_args.pool == address(0)) {
            revert SOT__constructor_invalidSovereignPool();
        }

        pool = _args.pool;

        if (_args.manager == address(0)) {
            revert SOT__constructor_invalidManager();
        }

        manager = _args.manager;

        if (_args.signer == address(0)) {
            revert SOT__constructor_invalidSigner();
        }

        solverReadSlot.signer = _args.signer;

        if (_args.liquidityProvider == address(0)) {
            revert SOT__constructor_invalidLiquidityProvider();
        }

        liquidityProvider = _args.liquidityProvider;

        // TODO: Bound
        maxDelay = _args.maxDelay;

        if (_args.solverMaxDiscountBips > SOTConstants.BIPS) {
            revert SOT__constructor_invalidSolverMaxDiscountBips();
        }

        solverMaxDiscountBips = _args.solverMaxDiscountBips;

        if (_args.oraclePriceMaxDiffBips > SOTConstants.BIPS) {
            revert SOT__constructor_invalidOraclePriceMaxDiffBips();
        }

        oraclePriceMaxDiffBips = _args.oraclePriceMaxDiffBips;

        if (_args.minAmmFeeGrowthInPips > _args.maxAmmFeeGrowthInPips) {
            revert SOT__constructor_invalidFeeGrowthBounds();
        }
        minAmmFeeGrowthInPips = _args.minAmmFeeGrowthInPips;

        maxAmmFeeGrowthInPips = _args.maxAmmFeeGrowthInPips;

        if (_args.minAmmFee > SOTConstants.BIPS) {
            revert SOT__constructor_invalidMinAmmFee();
        }

        minAmmFee = _args.minAmmFee;

        SOTParams.validatePriceBounds(_args.sqrtSpotPriceX96, _args.sqrtPriceLowX96, _args.sqrtPriceHighX96);

        // TODO: Should LM initially be paused?
        _ammState.setState(0, _args.sqrtSpotPriceX96, _args.sqrtPriceLowX96, _args.sqrtPriceHighX96);
    }

    /************************************************
     *  GETTER FUNCTIONS
     ***********************************************/

    function getAmmState()
        external
        view
        returns (uint160 sqrtSpotPriceX96, uint160 sqrtPriceLowX96, uint160 sqrtPriceHighX96)
    {
        (, sqrtSpotPriceX96, sqrtPriceLowX96, sqrtPriceHighX96) = _ammState.getState();
    }

    /**
        @notice Returns the AMM reserves assuming some AMM spot price
        @dev this is a temporary implementation of the function.
        // TODO: add correct reserves calculation.
     */
    function getReservesAtPrice(
        uint160 sqrtSpotPriceX96New
    ) external view returns (uint256 reserve0, uint256 reserve1) {
        (reserve0, reserve1) = ISovereignPool(pool).getReserves();

        (, uint160 sqrtSpotPriceX96Cache, uint160 sqrtPriceLowX96Cache, uint160 sqrtPriceHighX96Cache) = _ammState
            .getState();

        // Calculate liquidity available to be utilized in this swap
        uint128 effectiveLiquidity = getEffectiveLiquidity(
            sqrtSpotPriceX96Cache,
            sqrtPriceLowX96Cache,
            sqrtPriceHighX96Cache
        );

        (uint256 activeAmount0, uint256 activeAmount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtSpotPriceX96Cache,
            sqrtPriceLowX96Cache,
            sqrtPriceHighX96Cache,
            effectiveLiquidity
        );

        uint256 passiveAmount0 = reserve0 - activeAmount0;
        uint256 passiveAmount1 = reserve1 - activeAmount1;

        (uint256 postSwapActiveAmount0, uint256 postSwapActiveAmount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtSpotPriceX96New,
            sqrtPriceLowX96Cache,
            sqrtPriceHighX96Cache,
            effectiveLiquidity
        );

        reserve0 = passiveAmount0 + postSwapActiveAmount0;
        reserve1 = passiveAmount1 + postSwapActiveAmount1;
    }

    function domainSeparatorV4() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    function isPaused() external view returns (bool) {
        return _ammState.getFlag(SOTConstants.PAUSE_FLAG);
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
        solverReadSlot.signer = _signer;
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
    function setSolverFeeInBips(uint16 _solverFeeBipsToken0, uint16 _solverFeeBipsToken1) external onlyManager {
        if (
            _solverFeeBipsToken0 > SOTConstants.MAX_SOLVER_FEE_IN_BIPS ||
            _solverFeeBipsToken1 > SOTConstants.MAX_SOLVER_FEE_IN_BIPS
        ) {
            revert SOT__setSolverFeeInBips_invalidSolverFee();
        }

        solverReadSlot.solverFeeBipsToken0 = _solverFeeBipsToken0;
        solverReadSlot.solverFeeBipsToken1 = _solverFeeBipsToken1;
    }

    function setMaxAllowedQuotes(uint8 _maxAllowedQuotes) external onlyManager {
        if (_maxAllowedQuotes > SOTConstants.MAX_SOT_QUOTES_IN_BLOCK) {
            revert SOT__setMaxAllowedQuotes_invalidMaxAllowedQuotes();
        }
        solverReadSlot.maxAllowedQuotes = _maxAllowedQuotes;
    }

    /**
        @notice Toggles the pause flag which instantly pauses all critical functions except withdrawals
     */
    function setPause(bool _value) external onlyManager {
        _ammState.setFlag(SOTConstants.PAUSE_FLAG, _value);
    }

    /**
        @notice Sets the AMM position's square-root upper and lower price bounds
        @param _sqrtPriceLowX96 New square-root lower price bound
        @param _sqrtPriceHighX96 New square-root upper price bound
        @param _expectedSqrtSpotPriceLowerX96 Lower limit for expected spot price ( inclusive )
        @param _expectedSqrtSpotPriceUpperX96 Upper limit for expected spot price ( inclusive )
        @dev Can be used to utilize disproportionate token liquidity by tuning price bounds offchain
     */
    function setPriceBounds(
        uint160 _sqrtPriceLowX96,
        uint160 _sqrtPriceHighX96,
        uint160 _expectedSqrtSpotPriceLowerX96,
        uint160 _expectedSqrtSpotPriceUpperX96
    ) external onlyLiquidityProvider {
        _onlySpotPriceRange(_expectedSqrtSpotPriceLowerX96, _expectedSqrtSpotPriceUpperX96);
        // Check that lower bound is smaller than upper bound, and both are not 0
        // TODO: should we allow _sqrtPriceLowX96 = _sqrtPriceHighX96 here?
        if (_sqrtPriceLowX96 >= _sqrtPriceHighX96) {
            revert SOT__setPriceBounds_invalidPriceBounds();
        }

        // Check that the price bounds are within the MAX and MIN sqrt prices
        if (_sqrtPriceLowX96 < SOTConstants.MIN_SQRT_PRICE || _sqrtPriceHighX96 > SOTConstants.MAX_SQRT_PRICE) {
            revert SOT__setPriceBounds_invalidPriceBounds();
        }

        (uint32 flags, uint160 sqrtSpotPriceX96Cache, , ) = _ammState.getState();

        // Check that new price bounds don't exclude current spot price
        SOTParams.validatePriceBounds(sqrtSpotPriceX96Cache, _sqrtPriceLowX96, _sqrtPriceHighX96);

        _ammState.setState(flags, sqrtSpotPriceX96Cache, _sqrtPriceLowX96, _sqrtPriceHighX96);
    }

    /************************************************
     *  EXTERNAL FUNCTIONS
     ***********************************************/

    function getLiquidityQuote(
        ALMLiquidityQuoteInput memory _almLiquidityQuoteInput,
        bytes calldata _externalContext,
        bytes calldata /*_verifierData*/
    ) external override onlyPool onlyUnpaused nonReentrant returns (ALMLiquidityQuote memory liquidityQuote) {
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
        uint160 _expectedSqrtSpotPriceLowerX96,
        uint160 _expectedSqrtSpotPriceUpperX96
    )
        external
        onlyLiquidityProvider
        onlyUnpaused
        nonReentrant
        returns (uint256 amount0Deposited, uint256 amount1Deposited)
    {
        _onlySpotPriceRange(_expectedSqrtSpotPriceLowerX96, _expectedSqrtSpotPriceUpperX96);

        (amount0Deposited, amount1Deposited) = ISovereignPool(pool).depositLiquidity(
            _amount0,
            _amount1,
            liquidityProvider,
            '',
            ''
        );
    }

    function withdrawLiquidity(
        uint256 _amount0,
        uint256 _amount1,
        address _recipient,
        uint160 _expectedSqrtSpotPriceLowerX96,
        uint160 _expectedSqrtSpotPriceUpperX96
    ) external onlyLiquidityProvider nonReentrant {
        _onlySpotPriceRange(_expectedSqrtSpotPriceLowerX96, _expectedSqrtSpotPriceUpperX96);

        ISovereignPool(pool).withdrawLiquidity(_amount0, _amount1, liquidityProvider, _recipient, '');
    }

    function getSwapFeeInBips(
        bool _isZeroToOne,
        uint256 /**_amountIn*/,
        address /**_user*/,
        bytes memory _swapFeeModuleContext
    ) external view returns (SwapFeeModuleData memory swapFeeModuleData) {
        // Verification of branches is done during getLiquidityQuote
        if (_swapFeeModuleContext.length != 0) {
            // Solver Branch
            swapFeeModuleData.feeInBips = _isZeroToOne
                ? solverReadSlot.solverFeeBipsToken0
                : solverReadSlot.solverFeeBipsToken1;
        } else {
            // AMM Branch
            swapFeeModuleData.feeInBips = _getAMMFeeInBips(_isZeroToOne);
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

    function onSwapCallback(bool /*_isZeroToOne*/, uint256 /*_amountIn*/, uint256 /*_amountOut*/) external override {
        // Liquidity Quote callback by Sovereign Pool ( not needed here)
    }

    /************************************************
     *  INTERNAL FUNCTIONS
     ***********************************************/

    function _getAMMFeeInBips(bool isZeroToOne) internal view returns (uint32 feeInBips) {
        // TODO: Test if all the calculations are in bips.
        // TODO: Add some min and max bounds to AMM fee.
        SolverWriteSlot memory solverWriteSlotCache = solverWriteSlot;

        uint16 feeMin = isZeroToOne ? solverWriteSlotCache.feeMinToken0 : solverWriteSlotCache.feeMinToken1;
        uint16 feeMax = isZeroToOne ? solverWriteSlotCache.feeMaxToken0 : solverWriteSlotCache.feeMaxToken1;
        uint16 feeGrowthInPips = isZeroToOne
            ? solverWriteSlotCache.feeGrowthInPipsToken0
            : solverWriteSlotCache.feeGrowthInPipsToken1;

        feeInBips = Math
            .mulDiv(feeGrowthInPips, (block.timestamp - solverWriteSlotCache.lastProcessedSignatureTimestamp), 100)
            .toUint32();

        // Add minimum fee
        feeInBips += uint32(feeMin);
        // Cap fee if necessary
        if (feeInBips > uint32(feeMax)) {
            feeInBips = uint32(feeMax);
        }
    }

    function getEffectiveLiquidity(
        uint160 sqrtSpotPriceX96,
        uint160 sqrtPriceLowX96,
        uint160 sqrtPriceHighX96
    ) public view returns (uint128 effectiveLiquidity) {
        // Query current reserves
        // This already excludes poolManager and protocol fees
        (uint256 reserve0, uint256 reserve1) = ISovereignPool(pool).getReserves();

        uint128 liquidity0 = LiquidityAmounts.getLiquidityForAmount0(sqrtSpotPriceX96, sqrtPriceHighX96, reserve0);

        uint128 liquidity1 = LiquidityAmounts.getLiquidityForAmount1(sqrtPriceLowX96, sqrtSpotPriceX96, reserve1);

        console.log('sot.getEffectiveLiquidity liquidity0: ', liquidity0);
        console.log('sot.getEffectiveLiquidity liquidity1: ', liquidity1);

        if (liquidity0 < liquidity1) {
            effectiveLiquidity = liquidity0;
        } else {
            effectiveLiquidity = liquidity1;
        }

        console.log('sot.getEffectiveLiquidity effectiveLiquidity: ', effectiveLiquidity);
    }

    function _ammSwap(
        ALMLiquidityQuoteInput memory almLiquidityQuoteInput,
        ALMLiquidityQuote memory liquidityQuote
    ) internal {
        // Check that the fee path was chosen correctly
        if (almLiquidityQuoteInput.feeInBips != _getAMMFeeInBips(almLiquidityQuoteInput.isZeroToOne)) {
            revert SOT__getLiquidityQuote_invalidFeePath();
        }

        // Cache sqrt spot price, lower bound, and upper bound
        (, uint160 sqrtSpotPriceX96Cache, uint160 sqrtPriceLowX96Cache, uint160 sqrtPriceHighX96Cache) = _ammState
            .getState();

        // Calculate liquidity available to be utilized in this swap
        uint128 effectiveLiquidity = getEffectiveLiquidity(
            sqrtSpotPriceX96Cache,
            sqrtPriceLowX96Cache,
            sqrtPriceHighX96Cache
        );

        // Calculate amountOut according to CPMM math
        uint160 sqrtSpotPriceX96New;
        (sqrtSpotPriceX96New, liquidityQuote.amountInFilled, liquidityQuote.amountOut, ) = SwapMath.computeSwapStep(
            sqrtSpotPriceX96Cache,
            almLiquidityQuoteInput.isZeroToOne ? sqrtPriceLowX96Cache : sqrtPriceHighX96Cache,
            effectiveLiquidity,
            almLiquidityQuoteInput.amountInMinusFee.toInt256(), // always exact input swap
            0 // fees have already been deducted
        );

        _ammState.setA(sqrtSpotPriceX96New);
    }

    function _solverSwap(
        ALMLiquidityQuoteInput memory almLiquidityQuoteInput,
        bytes memory externalContext,
        ALMLiquidityQuote memory liquidityQuote
    ) internal {
        // @audit Verify if this is safe ( more info in SOTConcrete.t.sol with @audit tag)
        (SolverOrderType memory sot, bytes memory signature) = abi.decode(externalContext, (SolverOrderType, bytes));

        // Execute SOT swap
        SolverWriteSlot memory solverWriteSlotCache = solverWriteSlot;
        SolverReadSlot memory solverReadSlotCache = solverReadSlot;

        // Check that the fee path was chosen correctly
        if (
            almLiquidityQuoteInput.feeInBips !=
            (
                almLiquidityQuoteInput.isZeroToOne
                    ? solverReadSlot.solverFeeBipsToken0
                    : solverReadSlot.solverFeeBipsToken1
            )
        ) {
            revert SOT__getLiquidityQuote_invalidFeePath();
        }

        // An SOT only updates state if:
        // 1. It is the first SOT that updates state in the block.
        // 2. It was signed after the last processed signature timestamp.
        bool isDiscountedSolver = block.timestamp > solverWriteSlotCache.lastStateUpdateTimestamp &&
            (solverWriteSlotCache.lastProcessedSignatureTimestamp < sot.signatureTimestamp);

        uint8 quotesInCurrentBlock = block.timestamp > solverWriteSlotCache.lastProcessedQuoteTimestamp
            ? 1
            : solverWriteSlotCache.lastProcessedBlockQuoteCount + 1;

        if (quotesInCurrentBlock > solverReadSlotCache.maxAllowedQuotes) {
            revert SOT__getLiquidityQuote_maxSolverQuotesExceeded();
        }

        uint256 solverPriceX192 = isDiscountedSolver ? sot.solverPriceX192Discounted : sot.solverPriceX192Base;

        // Calculate the amountOut according to the quoted price
        liquidityQuote.amountOut = almLiquidityQuoteInput.isZeroToOne
            ? Math.mulDiv(almLiquidityQuoteInput.amountInMinusFee, solverPriceX192, SOTConstants.Q192)
            : Math.mulDiv(almLiquidityQuoteInput.amountInMinusFee, SOTConstants.Q192, solverPriceX192);
        liquidityQuote.amountInFilled = almLiquidityQuoteInput.amountInMinusFee;

        sot.validateFeeParams(minAmmFee, minAmmFeeGrowthInPips, maxAmmFeeGrowthInPips);

        sot.validateBasicParams(
            liquidityQuote.amountOut,
            almLiquidityQuoteInput.sender,
            almLiquidityQuoteInput.recipient,
            almLiquidityQuoteInput.amountInMinusFee,
            almLiquidityQuoteInput.isZeroToOne ? maxToken1VolumeToQuote : maxToken0VolumeToQuote,
            maxDelay,
            solverWriteSlotCache.alternatingNonceBitmap
        );

        SOTParams.validatePriceConsistency(
            _ammState,
            solverPriceX192.sqrt().toUint160(),
            sot.sqrtSpotPriceX96New,
            getSqrtOraclePriceX96(),
            oraclePriceMaxDiffBips,
            solverMaxDiscountBips
        );

        // Verify SOT quote signature
        // @audit: Verify that this is a safe way to check signatures
        bytes32 sotHash = sot.hashParams();
        if (!solverReadSlotCache.signer.isValidSignatureNow(_hashTypedDataV4(sotHash), signature)) {
            revert SOT__getLiquidityQuote_invalidSignature();
        }

        // Only update the pool state, if this is a discounted solver quote
        if (isDiscountedSolver) {
            solverWriteSlot = SolverWriteSlot({
                lastProcessedBlockQuoteCount: quotesInCurrentBlock,
                feeGrowthInPipsToken0: sot.feeGrowthInPipsToken0,
                feeMaxToken0: sot.feeMaxToken0,
                feeMinToken0: sot.feeMinToken0,
                feeGrowthInPipsToken1: sot.feeGrowthInPipsToken1,
                feeMaxToken1: sot.feeMaxToken1,
                feeMinToken1: sot.feeMinToken1,
                lastStateUpdateTimestamp: block.timestamp.toUint32(),
                lastProcessedQuoteTimestamp: block.timestamp.toUint32(),
                lastProcessedSignatureTimestamp: sot.signatureTimestamp,
                alternatingNonceBitmap: solverWriteSlotCache.alternatingNonceBitmap.flipNonce(sot.nonce)
            });

            _ammState.setA(sot.sqrtSpotPriceX96New);
        } else {
            solverWriteSlotCache.lastProcessedBlockQuoteCount = quotesInCurrentBlock;
            solverWriteSlotCache.lastProcessedQuoteTimestamp = block.timestamp.toUint32();
            solverWriteSlotCache.alternatingNonceBitmap = solverWriteSlotCache.alternatingNonceBitmap.flipNonce(
                sot.nonce
            );

            solverWriteSlot = solverWriteSlotCache;
        }
    }

    /************************************************
     *  PRIVATE FUNCTIONS
     ***********************************************/

    /**
        @notice Checks that the current AMM spot price is within the expected range.
        @param _expectedSqrtSpotPriceLowerX96 Lower limit for expected spot price. ( inclusive )
        @param _expectedSqrtSpotPriceUpperX96 Upper limit for expected spot price. ( inclusive )
        @dev if both _expectedSqrtSpotPriceUpperX96 and _expectedSqrtSpotPriceLowerX96 are 0,
             then no check is performed.
      */
    function _onlySpotPriceRange(
        uint160 _expectedSqrtSpotPriceLowerX96,
        uint160 _expectedSqrtSpotPriceUpperX96
    ) private view {
        if (_expectedSqrtSpotPriceUpperX96 + _expectedSqrtSpotPriceLowerX96 != 0) {
            uint160 sqrtSpotPriceX96 = _ammState.getA();

            // Check that spot price has not been manipulated before updating price bounds
            if (
                sqrtSpotPriceX96 > _expectedSqrtSpotPriceUpperX96 || sqrtSpotPriceX96 < _expectedSqrtSpotPriceLowerX96
            ) {
                revert SOT__setPriceBounds_invalidSqrtSpotPriceX96(sqrtSpotPriceX96);
            }
        }
    }

    function _onlyPool() private view {
        if (msg.sender != pool) {
            revert SOT__onlyPool();
        }
    }

    function _onlyManager() private view {
        if (msg.sender != manager) {
            revert SOT__onlyManager();
        }
    }

    function _onlyUnpaused() private view {
        // 0th bit of flags: Pause
        if (_ammState.getFlag(SOTConstants.PAUSE_FLAG)) {
            revert SOT__onlyUnpaused();
        }
    }

    function _onlyLiquidityProvider() private view {
        if (msg.sender != liquidityProvider) {
            revert SOT__onlyLiquidityProvider();
        }
    }
}
