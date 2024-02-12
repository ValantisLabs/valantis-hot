// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { SolverOrderType } from 'src/structs/SOTStructs.sol';
import { SOT } from 'src/SOT.sol';
import { IERC20 } from 'valantis-core/lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import { SafeERC20 } from 'valantis-core/lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol';
import { ISovereignPool } from 'valantis-core/src/pools/interfaces/ISovereignPool.sol';

contract SOTLiquidityProvider {
    using SafeERC20 for IERC20;

    address public owner;
    SOT public sot;

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

    function setSOT(address _sot) public onlyOwner {
        sot = SOT(_sot);
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

        token0.approve(address(sot), _amount0);
        token1.approve(address(sot), _amount1);

        sot.depositLiquidity(_amount0, _amount1, _expectedSqrtSpotPriceUpperX96, _expectedSqrtSpotPriceLowerX96);
    }

    function withdrawLiquidity(
        uint256 _amount0,
        uint256 _amount1,
        address _recipient,
        uint160 _expectedSqrtSpotPriceUpperX96,
        uint160 _expectedSqrtSpotPriceLowerX96
    ) public onlyOwner {
        sot.withdrawLiquidity(
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
        sot.setPriceBounds(
            _sqrtPriceLowX96,
            _sqrtPriceHighX96,
            _expectedSqrtSpotPriceUpperX96,
            _expectedSqrtSpotPriceLowerX96
        );
    }
}
