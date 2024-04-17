// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface IArrakisPublicVaultRouter {
    // #region view functions.

    /// @notice getMintAmounts used to get the shares we can mint from some max amounts.
    /// @param vault_ meta vault address.
    /// @param maxAmount0_ maximum amount of token0 user want to contribute.
    /// @param maxAmount1_ maximum amount of token1 user want to contribute.
    /// @return shareToMint maximum amount of share user can get for 'maxAmount0_' and 'maxAmount1_'.
    /// @return amount0ToDeposit amount of token0 user should deposit into the vault for minting 'shareToMint'.
    /// @return amount1ToDeposit amount of token1 user should deposit into the vault for minting 'shareToMint'.
    function getMintAmounts(
        address vault_,
        uint256 maxAmount0_,
        uint256 maxAmount1_
    ) external view returns (uint256 shareToMint, uint256 amount0ToDeposit, uint256 amount1ToDeposit);

    // #endregion view functions.
}
