// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import 'forge-std/Script.sol';

import { Math } from 'valantis-core/lib/openzeppelin-contracts/contracts/utils/math/Math.sol';
import { SafeCast } from 'valantis-core/lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol';

import { SOT } from 'src/SOT.sol';
import { MockLiquidityProvider } from 'test/mocks/MockLiquidityProvider.sol';
import { SOTConstructorArgs, SolverOrderType } from 'src/structs/SOTStructs.sol';
import { SOTBase } from 'test/base/SOTBase.t.sol';
import { SOTConstants } from 'src/libraries/SOTConstants.sol';

import {
    SovereignPool,
    SovereignPoolBase,
    SovereignPoolConstructorArgs,
    SovereignPoolSwapParams,
    SovereignPoolSwapContextData
} from 'valantis-core/test/base/SovereignPoolBase.t.sol';

import { MockToken } from 'test/mocks/MockToken.sol';
import { MockChainlinkOracle } from 'test/mocks/MockChainlinkOracle.sol';
import { SOTDeployer } from 'test/deployers/SOTDeployer.sol';
import { SovereignPoolDeployer } from 'valantis-core/test/deployers/SovereignPoolDeployer.sol';

import { AggregatorV3Interface } from 'src/vendor/chainlink/AggregatorV3Interface.sol';
import { IERC20 } from 'valantis-core/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';

import { DeployHelper } from 'scripts/utils/DeployHelper.sol';
import { Strings } from 'valantis-core/lib/openzeppelin-contracts/contracts/utils/Strings.sol';

contract SOTSwapScript is Script {
    using SafeCast for uint256;

    function run() external {
        string memory path = DeployHelper.getPath();
        string memory json = vm.readFile(path);

        vm.startBroadcast(vm.envUint('DEPLOYER_PRIVATE_KEY'));

        SovereignPool pool = SovereignPool(vm.parseJsonAddress(json, '.SovereignPool'));
        address master = vm.parseJsonAddress(json, '.DeployerPublicKey');
        SOT sot = SOT(pool.alm());

        IERC20 token0 = IERC20(pool.token0());
        IERC20 token1 = IERC20(pool.token1());

        AggregatorV3Interface feedToken0 = AggregatorV3Interface(sot.feedToken0());
        AggregatorV3Interface feedToken1 = AggregatorV3Interface(sot.feedToken1());

        token0.approve(address(pool), type(uint256).max);
        token1.approve(address(pool), type(uint256).max);

        bool isZeroToOne = true;
        uint256 amountIn = 0x0000000000000000000000000000000000000000000000000000000000000db7;

        // Note: Update these to relevant values, before making an SOT Swap. Not needed for AMM swap.
        (uint160 sqrtSpotPriceX96, , ) = sot.getAMMState();
        uint256 spotPrice = Math.mulDiv(sqrtSpotPriceX96, sqrtSpotPriceX96, 1 << 192);

        console.log('Spot Price AMM : ', spotPrice);

        SolverOrderType memory sotParams = SolverOrderType({
            amountInMax: amountIn,
            solverPriceX192Discounted: 0x00000000112574833ea203a54b9c8bb3e0cad2df956228097c073212c9144a43,
            solverPriceX192Base: 0x00000000110fb9a38ba1365219cfbb2b6236cf4b777ed1a91ee635a0a210633d,
            sqrtSpotPriceX96New: 0x00000000000000000000000000000000000041ec95e6a4a2992195407e5d7055,
            authorizedSender: master,
            authorizedRecipient: master,
            signatureTimestamp: (block.timestamp).toUint32(),
            expiry: 120, // 2 minutes
            feeMinToken0: 10, // 0.1%
            feeMaxToken0: 100, // 1%
            feeGrowthE6Token0: 500, // 5 bips per second
            feeMinToken1: 10,
            feeMaxToken1: 100,
            feeGrowthE6Token1: 500,
            nonce: 39,
            expectedFlag: 0,
            isZeroToOne: isZeroToOne
        });

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            vm.envUint('DEPLOYER_PRIVATE_KEY'),
            keccak256(
                abi.encodePacked(
                    '\x19\x01',
                    sot.domainSeparatorV4(),
                    keccak256(abi.encode(SOTConstants.SOT_TYPEHASH, sotParams))
                )
            )
        );

        SovereignPoolSwapContextData memory data = SovereignPoolSwapContextData({
            externalContext: abi.encode(sotParams, abi.encodePacked(r, s, bytes1(v))),
            verifierContext: bytes(''),
            swapCallbackContext: bytes(''),
            swapFeeModuleContext: bytes('1')
        });

        SovereignPoolSwapParams memory params = SovereignPoolSwapParams({
            isSwapCallback: false,
            isZeroToOne: isZeroToOne,
            amountIn: amountIn,
            amountOutMin: 0,
            recipient: master,
            deadline: block.timestamp + 5, // If swaps fail, try to update this to a higher value
            swapTokenOut: isZeroToOne ? token1 : token0,
            swapContext: data
        });

        pool.swap(params);

        vm.stopBroadcast();
    }
}
