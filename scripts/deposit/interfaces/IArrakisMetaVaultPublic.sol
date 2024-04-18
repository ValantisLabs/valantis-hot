// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface IArrakisMetaVaultPublic {
    // #region errors.

    error MintZero();
    error BurnZero();
    error BurnOverflow();

    // #endregion errors.

    // #region events.

    /// @notice event emitted when a user mint some shares on a public vault.
    /// @param shares amount of shares minted.
    /// @param receiver address that will receive the LP token (shares).
    /// @param amount0 amount of token0 needed to mint shares.
    /// @param amount1 amount of token1 needed to mint shares.
    event LogMint(uint256 shares, address receiver, uint256 amount0, uint256 amount1);

    /// @notice event emitted when a user burn some of his shares.
    /// @param shares amount of share burned by the user.
    /// @param receiver address that will receive amounts of tokens
    /// related to burning the shares.
    /// @param amount0 amount of token0 that is collected from burning shares.
    /// @param amount1 amount of token1 that is collected from burning shares.
    event LogBurn(uint256 shares, address receiver, uint256 amount0, uint256 amount1);

    // #endregion events.

    /// @notice function used to mint share of the vault position
    /// @param shares_ amount representing the part of the position owned by receiver.
    /// @param receiver_ address where share token will be sent.
    /// @return amount0 amount of token0 deposited.
    /// @return amount1 amount of token1 deposited.
    function mint(uint256 shares_, address receiver_) external payable returns (uint256 amount0, uint256 amount1);

    /// @notice function used to burn share of the vault position.
    /// @param shares_ amount of share that will be burn.
    /// @param receiver_ address where underlying tokens will be sent.
    /// @return amount0 amount of token0 withdrawn.
    /// @return amount1 amount of token1 withdrawn.
    function burn(uint256 shares_, address receiver_) external returns (uint256 amount0, uint256 amount1);
}
