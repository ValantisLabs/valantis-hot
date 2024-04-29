// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import { ISOTOracle } from 'src/interfaces/ISOTOracle.sol';
import { AggregatorV3Interface } from 'src/vendor/chainlink/AggregatorV3Interface.sol';

import { SwapFeeModuleData } from 'valantis-core/src/swap-fee-modules/interfaces/ISwapFeeModule.sol';
import { ALMLiquidityQuote, ALMLiquidityQuoteInput } from 'valantis-core/src/alm/interfaces/ISovereignALM.sol';

interface ISOT is ISOTOracle {
    /************************************************
     *  EVENTS
     ***********************************************/

    event ALMDeployed(string indexed name, address alm, address pool);
    event AMMFeeSet(uint16 feeMaxToken0, uint16 feeMaxToken1);
    event EffectiveAMMLiquidityUpdate(uint256 effectiveAMMLiquidity);
    event FeedSetApproval();
    event ManagerUpdate(address indexed manager);
    event MaxAllowedQuoteSet(uint8 maxQuotes);
    event MaxOracleDeviationBipsSet(uint16 maxOracleDeviationBips);
    event MaxTokenVolumeSet(uint256 amount0, uint256 amount1);
    event OracleFeedsSet(address feed0, address feed1);
    event PauseSet(bool pause);
    event PostWithdrawalLiquidityCapped(
        uint160 sqrtSpotPriceX96,
        uint128 preWithdrawalLiquidity,
        uint128 postWithdrawalLiquidity
    );
    event PriceBoundSet(uint160 sqrtPriceLowX96, uint160 sqrtPriceHighX96);
    event SignerUpdate(address indexed signer);
    event SolverFeeSet(uint16 fee0Bips, uint16 fee1Bips);
    event SolverSwap(bytes32 sotHash);

    /************************************************
     *  VIEW FUNCTIONS
     ***********************************************/

    function domainSeparatorV4() external view returns (bytes32);

    function effectiveAMMLiquidity() external view returns (uint128);

    function getAMMState()
        external
        view
        returns (uint160 sqrtSpotPriceX96, uint160 sqrtPriceLowX96, uint160 sqrtPriceHighX96);

    function getReservesAtPrice(uint160 sqrtSpotPriceX96New) external view returns (uint256 reserve0, uint256 reserve1);

    function isPaused() external view returns (bool);

    function liquidityProvider() external view returns (address);

    function manager() external view returns (address);

    function maxAMMFeeGrowthE6() external view returns (uint16);

    function maxDelay() external view returns (uint32);

    function maxOracleDeviationBips() external view returns (uint16);

    function maxOracleDeviationBound() external view returns (uint16);

    function maxToken0VolumeToQuote() external view returns (uint256);

    function maxToken1VolumeToQuote() external view returns (uint256);

    function minAMMFee() external view returns (uint16);

    function minAMMFeeGrowthE6() external view returns (uint16);

    function pool() external view returns (address);

    function solverMaxDiscountBips() external view returns (uint16);

    function solverReadSlot()
        external
        view
        returns (
            bool isPaused,
            uint8 maxAllowedQuotes,
            uint16 maxOracleDeviationBips,
            uint16 solverFeeBipsToken0,
            uint16 solverFeeBipsToken1,
            address signer
        );

    function solverWriteSlot()
        external
        view
        returns (
            uint8 lastProcessedBlockQuoteCount,
            uint16 feeGrowthE6Token0,
            uint16 feeMaxToken0,
            uint16 feeMinToken0,
            uint16 feeGrowthE6Token1,
            uint16 feeMaxToken1,
            uint16 feeMinToken1,
            uint32 lastStateUpdateTimestamp,
            uint32 lastProcessedQuoteTimestamp,
            uint32 lastProcessedSignatureTimestamp,
            uint56 alternatingNonceBitmap
        );

    /************************************************
     *   FUNCTIONS
     ***********************************************/

    function setManager(address _manager) external;

    function setMaxAllowedQuotes(uint8 _maxAllowedQuotes) external;

    function setMaxOracleDeviationBips(uint16 _maxOracleDeviationBips) external;

    function setMaxTokenVolumes(uint256 _maxToken0VolumeToQuote, uint256 _maxToken1VolumeToQuote) external;

    function setPause(bool _value) external;

    function setPriceBounds(
        uint160 _sqrtPriceLowX96,
        uint160 _sqrtPriceHighX96,
        uint160 _expectedSqrtSpotPriceLowerX96,
        uint160 _expectedSqrtSpotPriceUpperX96
    ) external;

    function setSigner(address _signer) external;

    function setSolverFeeInBips(uint16 _solverFeeBipsToken0, uint16 _solverFeeBipsToken1) external;

    function depositLiquidity(
        uint256 _amount0,
        uint256 _amount1,
        uint160 _expectedSqrtSpotPriceLowerX96,
        uint160 _expectedSqrtSpotPriceUpperX96
    ) external returns (uint256 amount0Deposited, uint256 amount1Deposited);

    function withdrawLiquidity(
        uint256 _amount0,
        uint256 _amount1,
        address _recipient,
        uint160 _expectedSqrtSpotPriceLowerX96,
        uint160 _expectedSqrtSpotPriceUpperX96
    ) external;
}
