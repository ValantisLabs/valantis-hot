// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

struct SwapFeeModuleData {
    uint256 feeInBips;
    bytes internalContext;
}

interface ISwapFeeModuleMinimal {
    function getSwapFeeInBips(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn,
        address _user,
        bytes memory _swapFeeModuleContext
    ) external returns (SwapFeeModuleData memory swapFeeModuleData);
}
