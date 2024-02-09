// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import 'forge-std/console.sol';

import {
    SovereignPool,
    SovereignPoolBase,
    SovereignPoolConstructorArgs
} from 'valantis-core/test/base/SovereignPoolBase.t.sol';
import { Base } from 'valantis-core/test/base/Base.sol';

import { MockChainlinkOracle } from 'test/mocks/MockChainlinkOracle.sol';

import { SOTSigner } from 'test/helpers/SOTSigner.sol';

import { SOT } from 'src/SOT.sol';
import { SOTConstants } from 'src/libraries/SOTConstants.sol';
import { SOTConstructorArgs, SolverOrderType, SolverWriteSlot } from 'src/structs/SOTStructs.sol';
import { SOTOracle } from 'src/SOTOracle.sol';
import { SOTOracleHelper } from 'test/helpers/SOTOracleHelper.sol';

import { SOTDeployer } from 'test/deployers/SOTDeployer.sol';
import { SafeCast } from 'valantis-core/lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol';

import { Math } from 'valantis-core/lib/openzeppelin-contracts/contracts/utils/math/Math.sol';

import { TightPack } from 'src/libraries/utils/TightPack.sol';

contract SOTBase is SovereignPoolBase, SOTDeployer {
    using SafeCast for uint256;
    using TightPack for TightPack.PackedState;

    struct PoolState {
        uint160 spotPrice;
        uint256 reserve0;
        uint256 reserve1;
        uint256 managerFee0;
        uint256 managerFee1;
    }

    uint256 public EOASignerPrivateKey = 0x12345;
    address public EOASigner = vm.addr(EOASignerPrivateKey);

    SOT public sot;

    SOTSigner public mockSigner;

    MockChainlinkOracle public feedToken0;
    MockChainlinkOracle public feedToken1;

    function setUp() public virtual override {
        _setupBase();

        (feedToken0, feedToken1) = deployChainlinkOracles(8, 8);

        mockSigner = new SOTSigner();

        // Set initial price to 2000 for token0 and 1 for token1 (Similar to Eth/USDC pair)
        feedToken0.updateAnswer(2000e8);
        feedToken1.updateAnswer(1e8);

        SovereignPoolConstructorArgs memory poolArgs = _generateDefaultConstructorArgs();
        pool = this.deploySovereignPool(poolArgs);
        sot = deployAndSetDefaultSOT(pool);

        _addToContractsToApprove(address(pool));
        _addToContractsToApprove(address(sot));
    }

    function deployAndSetDefaultSOT(SovereignPool _pool) public returns (SOT _sot) {
        SOTConstructorArgs memory args = SOTConstructorArgs({
            pool: address(_pool),
            manager: address(this),
            signer: address(mockSigner),
            liquidityProvider: address(this),
            feedToken0: address(feedToken0),
            feedToken1: address(feedToken1),
            sqrtSpotPriceX96: getSqrtPriceX96(2000 * (10 ** feedToken0.decimals()), 1 * (10 ** feedToken1.decimals())),
            sqrtPriceLowX96: getSqrtPriceX96(1500 * (10 ** feedToken0.decimals()), 1 * (10 ** feedToken1.decimals())),
            sqrtPriceHighX96: getSqrtPriceX96(2500 * (10 ** feedToken0.decimals()), 1 * (10 ** feedToken1.decimals())),
            maxDelay: 9 minutes,
            maxOracleUpdateDuration: 10 minutes,
            solverMaxDiscountBips: 200, // 2%
            oraclePriceMaxDiffBips: 5000, // 50%
            minAmmFeeGrowth: 1,
            maxAmmFeeGrowth: 100,
            minAmmFee: 1 // 0.01%
        });

        vm.startPrank(_pool.poolManager());
        _sot = this.deploySOT(_pool, args);
        _pool.setALM(address(_sot));
        _pool.setSwapFeeModule(address(_sot));
        vm.stopPrank();
    }

    function deployChainlinkOracles(
        uint8 feedToken0Decimals,
        uint8 feedToken1Decimals
    ) public returns (MockChainlinkOracle _feedToken0, MockChainlinkOracle _feedToken1) {
        _feedToken0 = new MockChainlinkOracle(feedToken0Decimals);
        _feedToken1 = new MockChainlinkOracle(feedToken1Decimals);

        return (_feedToken0, _feedToken1);
    }

    /// @dev This is only used for testing, during deployment SOTOracle is inherited by SOT
    function deploySOTOracleIndependently(
        MockChainlinkOracle _feedToken0,
        MockChainlinkOracle _feedToken1,
        uint32 _maxOracleUpdateDuration
    ) public returns (SOTOracle oracle) {
        oracle = new SOTOracle(
            address(pool.token0()),
            address(pool.token1()),
            address(_feedToken0),
            address(_feedToken1),
            _maxOracleUpdateDuration
        );
    }

    /// @dev This is only used for testing, during deployment SOTOracle is inherited by SOT
    function deploySOTOracleHelper(
        MockChainlinkOracle _feedToken0,
        MockChainlinkOracle _feedToken1,
        uint32 _maxOracleUpdateDuration
    ) public returns (SOTOracleHelper oracle) {
        oracle = new SOTOracleHelper(
            address(pool.token0()),
            address(pool.token1()),
            address(_feedToken0),
            address(_feedToken1),
            _maxOracleUpdateDuration
        );
    }

    function _getSensibleSOTParams() internal returns (SolverOrderType memory sotParams) {
        // Sensible Defaults
        sotParams = SolverOrderType({
            amountInMax: 100e18,
            solverPriceX192Discounted: 1980 << 192, // 1% discount to first solver
            solverPriceX192Base: 2000 << 192,
            sqrtSpotPriceX96New: getSqrtPriceX96(
                2005 * (10 ** feedToken0.decimals()),
                1 * (10 ** feedToken1.decimals())
            ), // AMM spot price 2005
            authorizedSender: address(this),
            authorizedRecipient: makeAddr('RECIPIENT'),
            signatureTimestamp: (block.timestamp).toUint32(),
            expiry: 24, // 2 Blocks
            feeMinToken0: 10, // 0.1%
            feeMaxToken0: 100, // 1%
            feeGrowthToken0: 5, // 5 bips per second
            feeMinToken1: 10,
            feeMaxToken1: 100,
            feeGrowthToken1: 5,
            nonce: 1,
            expectedFlag: 0
        });
    }

    function getSqrtPriceX96(uint256 price0USD, uint256 price1USD) public view returns (uint160 sqrtOraclePriceX96) {
        uint256 oracle0Base = 10 ** feedToken0.decimals();
        uint256 oracle1Base = 10 ** feedToken1.decimals();
        uint256 token0Base = 10 ** token0.decimals();
        uint256 token1Base = 10 ** token1.decimals();

        uint256 oraclePriceX96 = Math.mulDiv(
            price0USD * oracle1Base * token1Base,
            1 << 96,
            price1USD * oracle0Base * token0Base
        );

        return (Math.sqrt(oraclePriceX96) << 48).toUint160();
    }

    function getEOASignedQuote(
        SolverOrderType memory sotParams,
        uint256 privateKey
    ) public view returns (bytes memory signedQuoteExternalContext) {
        bytes32 digest = keccak256(
            abi.encodePacked(
                '\x19\x01',
                sot.domainSeparatorV4(),
                keccak256(abi.encode(SOTConstants.SOT_TYPEHASH, sotParams))
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

        bytes memory signature = abi.encodePacked(r, s, bytes1(v));

        signedQuoteExternalContext = abi.encode(sotParams, signature);
    }

    function getPoolState() public view returns (PoolState memory state) {
        (uint256 poolReserve0, uint256 poolReserve1) = pool.getReserves();
        (uint256 managerFee0, uint256 managerFee1) = pool.getPoolManagerFees();
        uint160 sqrtSpotPriceX96 = sot.getSqrtSpotPriceX96();

        state = PoolState({
            spotPrice: sqrtSpotPriceX96,
            reserve0: poolReserve0,
            reserve1: poolReserve1,
            managerFee0: managerFee0,
            managerFee1: managerFee1
        });
    }

    function checkPoolState(PoolState memory actual, PoolState memory expected) public {
        assertEq(actual.reserve0, expected.reserve0, 'checkPoolState: reserve0');
        assertEq(actual.reserve1, expected.reserve1, 'checkPoolState: reserve1');
        assertEq(actual.spotPrice, expected.spotPrice, 'checkPoolState: spotPrice');
        assertEq(actual.managerFee0, expected.managerFee0, 'checkPoolState: managerFee0');
        assertEq(actual.managerFee1, expected.managerFee1, 'checkPoolState: managerFee1');
    }

    function checkSolverWriteSlot(SolverWriteSlot memory actual, SolverWriteSlot memory expected) public {
        assertEq(
            actual.lastProcessedBlockQuoteCount,
            expected.lastProcessedBlockQuoteCount,
            'checkSolverWriteSlot: lastProcessedBlockQuoteCount'
        );
        assertEq(actual.feeGrowthToken0, expected.feeGrowthToken0, 'checkSolverWriteSlot: feeGrowthToken0');
        assertEq(actual.feeMaxToken0, expected.feeMaxToken0, 'checkSolverWriteSlot: feeMaxToken0');
        assertEq(actual.feeMinToken0, expected.feeMinToken0, 'checkSolverWriteSlot: feeMinToken0');
        assertEq(actual.feeGrowthToken1, expected.feeGrowthToken1, 'checkSolverWriteSlot: feeGrowthToken1');
        assertEq(actual.feeMaxToken1, expected.feeMaxToken1, 'checkSolverWriteSlot: feeMaxToken1');
        assertEq(actual.feeMinToken1, expected.feeMinToken1, 'checkSolverWriteSlot: feeMinToken1');
        assertEq(
            actual.lastStateUpdateTimestamp,
            expected.lastStateUpdateTimestamp,
            'checkSolverWriteSlot: lastStateUpdateTimestamp'
        );
        assertEq(
            actual.lastProcessedQuoteTimestamp,
            expected.lastProcessedQuoteTimestamp,
            'checkSolverWriteSlot: lastProcessedQuoteTimestamp'
        );
        assertEq(
            actual.lastProcessedSignatureTimestamp,
            expected.lastProcessedSignatureTimestamp,
            'checkSolverWriteSlot: lastProcessedSignatureTimestamp'
        );
        assertEq(
            actual.alternatingNonceBitmap,
            expected.alternatingNonceBitmap,
            'checkSolverWriteSlot: alternatingNonceBitmap'
        );
    }
}
