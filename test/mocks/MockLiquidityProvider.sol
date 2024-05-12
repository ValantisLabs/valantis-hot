// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { IERC20 } from '../../lib/valantis-core/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import {
    SafeERC20
} from '../../lib/valantis-core/lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol';
import { ISovereignPool } from '../../lib/valantis-core/src/pools/interfaces/ISovereignPool.sol';

import { HybridOrderType } from '../../src/structs/HOTStructs.sol';
import { HOT } from '../../src/HOT.sol';

contract MockLiquidityProvider {
    using SafeERC20 for IERC20;

    address public owner;
    HOT public hot;

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, 'Only Owner');
        _;
    }

    function setOwner(address _owner) public onlyOwner {
        owner = _owner;
    }

    function setHOT(address _hot) public onlyOwner {
        hot = HOT(_hot);
    }

    function depositLiquidity(
        address _pool,
        uint256 _amount0,
        uint256 _amount1,
        uint160 _expectedSqrtSpotPriceUpperX96,
        uint160 _expectedSqrtSpotPriceLowerX96
    ) public onlyOwner {
        IERC20 token0 = IERC20(ISovereignPool(_pool).token0());
        IERC20 token1 = IERC20(ISovereignPool(_pool).token1());

        token0.approve(address(hot), _amount0);
        token1.approve(address(hot), _amount1);

        hot.depositLiquidity(_amount0, _amount1, _expectedSqrtSpotPriceUpperX96, _expectedSqrtSpotPriceLowerX96);
    }

    function withdrawLiquidity(
        uint256 _amount0,
        uint256 _amount1,
        address _recipient,
        uint160 _expectedSqrtSpotPriceUpperX96,
        uint160 _expectedSqrtSpotPriceLowerX96
    ) public onlyOwner {
        hot.withdrawLiquidity(
            _amount0,
            _amount1,
            _recipient,
            _expectedSqrtSpotPriceUpperX96,
            _expectedSqrtSpotPriceLowerX96
        );
    }

    function setPriceBounds(
        uint160 _sqrtPriceLowX96,
        uint160 _sqrtPriceHighX96,
        uint160 _expectedSqrtSpotPriceUpperX96,
        uint160 _expectedSqrtSpotPriceLowerX96
    ) public onlyOwner {
        hot.setPriceBounds(
            _sqrtPriceLowX96,
            _sqrtPriceHighX96,
            _expectedSqrtSpotPriceUpperX96,
            _expectedSqrtSpotPriceLowerX96
        );
    }
}
