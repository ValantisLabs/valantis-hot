// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import { IHOTOracle } from './IHOTOracle.sol';
import { AggregatorV3Interface } from '../vendor/chainlink/AggregatorV3Interface.sol';

import { SwapFeeModuleData } from '../../lib/valantis-core/src/swap-fee-modules/interfaces/ISwapFeeModule.sol';
import {
    ALMLiquidityQuote,
    ALMLiquidityQuoteInput
} from '../../lib/valantis-core/src/alm/interfaces/ISovereignALM.sol';

interface IHOT is IHOTOracle {
    /************************************************
     *  EVENTS
     ***********************************************/

    event ALMDeployed(string indexed name, address alm, address pool);
    event AMMFeeSet(uint16 feeMaxToken0, uint16 feeMaxToken1);
    event OracleFeedsSet();
    event ManagerUpdate(address indexed manager);
    event MaxAllowedQuoteSet(uint8 maxQuotes);
    event MaxOracleDeviationBipsSet(uint16 maxOracleDeviationBipsLower, uint16 maxOracleDeviationBipsUpper);
    event MaxTokenVolumeSet(uint256 amount0, uint256 amount1);
    event OracleFeedsProposed(address feed0, address feed1);
    event PauseSet(bool pause);
    event PostWithdrawalLiquidityCapped(
        uint160 sqrtSpotPriceX96,
        uint128 preWithdrawalLiquidity,
        uint128 postWithdrawalLiquidity
    );
    event PriceBoundSet(uint160 sqrtPriceLowX96, uint160 sqrtPriceHighX96);
    event SignerUpdate(address indexed signer);
    event HotFeeSet(uint16 fee0Bips, uint16 fee1Bips);
    event HotSwap(bytes32 hotHash);

    /************************************************
     *  VIEW FUNCTIONS
     ***********************************************/
    function effectiveAMMLiquidity() external view returns (uint128);

    function getAMMState()
        external
        view
        returns (uint160 sqrtSpotPriceX96, uint160 sqrtPriceLowX96, uint160 sqrtPriceHighX96);

    function getReservesAtPrice(uint160 sqrtSpotPriceX96New) external view returns (uint256 reserve0, uint256 reserve1);

    function manager() external view returns (address);

    function maxTokenVolumes() external view returns (uint256, uint256);

    function proposedFeedToken0() external view returns (address);
    function proposedFeedToken1() external view returns (address);

    function hotReadSlot()
        external
        view
        returns (
            bool isPaused,
            uint8 maxAllowedQuotes,
            uint16 maxOracleDeviationBipsLower,
            uint16 maxOracleDeviationBipsUpper,
            uint16 solverFeeBipsToken0,
            uint16 solverFeeBipsToken1,
            address signer
        );

    function hotWriteSlot()
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

    function proposeFeeds(address _feedToken0, address _feedToken1) external;

    function setFeeds() external;

    function setManager(address _manager) external;

    function setMaxAllowedQuotes(uint8 _maxAllowedQuotes) external;

    function setMaxOracleDeviationBips(
        uint16 _maxOracleDeviationBipsLower,
        uint16 _maxOracleDeviationBipsUpper
    ) external;

    function setMaxTokenVolumes(uint256 _maxToken0VolumeToQuote, uint256 _maxToken1VolumeToQuote) external;

    function setPause(bool _value) external;

    function setPriceBounds(
        uint160 _sqrtPriceLowX96,
        uint160 _sqrtPriceHighX96,
        uint160 _expectedSqrtSpotPriceLowerX96,
        uint160 _expectedSqrtSpotPriceUpperX96
    ) external;

    function setSigner(address _signer) external;

    function setHotFeeInBips(uint16 _hotFeeBipsToken0, uint16 _hotFeeBipsToken1) external;

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
