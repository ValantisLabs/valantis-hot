// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

/// @title IArrakisMetaVault
/// @notice IArrakisMetaVault is a vault that is able to invest dynamically deposited
/// tokens into protocols through his module.
interface IArrakisMetaVault {
    // #region errors.

    /// @dev triggered when an address that should not
    /// be zero is equal to address zero.
    // TODO remove the argument.
    error AddressZero(string property);

    /// @dev triggered when tokens are already initialized
    error AddressNotZero();

    /// @dev triggered when the caller is different than
    /// the manager.
    error OnlyManager(address caller, address manager);

    /// @dev triggered when a low level call failed during
    /// execution.
    error CallFailed();

    /// @dev triggered when manager try to set the active
    /// module as active.
    error SameModule();

    /// @dev triggered when owner of the vault try to set the
    /// manager with the current manager.
    error SameManager();

    /// @dev triggered when all tokens withdrawal has been done
    /// during a switch of module.
    error ModuleNotEmpty(uint256 amount0, uint256 amount1);

    /// @dev triggered when owner try to whitelist a module
    /// that has been already whitelisted.
    error AlreadyWhitelisted(address module);

    /// @dev triggered when owner try to blacklist a module
    /// that has not been whitelisted.
    error NotWhitelistedModule(address module);

    /// @dev triggered when owner try to blacklist the active module.
    error ActiveModule();

    /// @dev triggered during vault creation if token0 address is greater than
    /// token1 address.
    error Token0GtToken1();

    /// @dev triggered during vault creation if token0 address is equal to
    /// token1 address.
    error Token0EqToken1();

    /// @dev triggered when whitelisting action is occuring and module's beacon
    /// is not whitelisted on module registry.
    error NotWhitelistedBeacon();

    /// @dev triggered when guardian of the whitelisting module is different than
    /// the guardian of the registry.
    error NotSameGuardian();

    /// @dev triggered when a function logic is not implemented.
    error NotImplemented();

    /// @dev triggered when two arrays suppposed to have the same length, have different length.
    error ArrayNotSameLength();

    /// @dev triggered when function is called by someone else than the owner.
    error OnlyOwner();

    // #endregion errors.

    // #region events.

    /// @notice Event describing a manager fee withdrawal.
    /// @param amount0 amount of token0 that manager has earned and will be transfered.
    /// @param amount1 amount of token1 that manager has earned and will be transfered.
    event LogWithdrawManagerBalance(uint256 amount0, uint256 amount1);

    /// @notice Event describing owner setting the manager.
    /// @param manager address of manager that will manage the portfolio.
    event LogSetManager(address manager);

    /// @notice Event describing manager setting the module.
    /// @param module address of the new active module.
    /// @param payloads data payloads for initializing positions on the new module.
    event LogSetModule(address module, bytes[] payloads);

    /// @notice Event describing default module that the vault will be initialized with.
    /// @param module address of the default module.
    event LogSetFirstModule(address module);

    /// @notice Event describing list of modules that has been whitelisted by owner.
    /// @param modules list of addresses corresponding to new modules now available
    /// to be activated by manager.
    event LogWhiteListedModules(address[] modules);

    /// @notice Event describing whitelisted of the first module during vault creation.
    /// @param module default activation.
    event LogWhitelistedModule(address module);

    /// @notice Event describing blacklisting action of modules by owner.
    /// @param modules list of addresses corresponding to old modules that has been
    /// blacklisted.
    event LogBlackListedModules(address[] modules);

    // #endregion events.

    /// @notice function used to initialize tokens.
    /// @param token0_ address of the first token of the token pair.
    /// @param token1_ address of the second token of the token pair.
    function initializeTokens(address token0_, address token1_) external;

    /// @notice function used to initialize default module.
    /// @param module_ address of the default module.
    function initialize(address module_) external;

    /// @notice function used to set module
    /// @param module_ address of the new module
    /// @param payloads_ datas to initialize/rebalance on the new module
    function setModule(address module_, bytes[] calldata payloads_) external;

    /// @notice function used to whitelist modules that can used by manager.
    /// @param beacons_ array of beacons addresses to use for modules creation.
    /// @param data_ array of payload to use for modules creation.
    function whitelistModules(address[] calldata beacons_, bytes[] calldata data_) external;

    /// @notice function used to blacklist modules that can used by manager.
    /// @param modules_ array of module addresses to be blacklisted.
    function blacklistModules(address[] calldata modules_) external;

    // #region view functions.

    /// @notice function used to get the list of modules whitelisted.
    /// @return modules whitelisted modules addresses.
    function whitelistedModules() external view returns (address[] memory modules);

    /// @notice function used to get the amount of token0 and token1 sitting
    /// on the position.
    /// @return amount0 the amount of token0 sitting on the position.
    /// @return amount1 the amount of token1 sitting on the position.
    function totalUnderlying() external view returns (uint256 amount0, uint256 amount1);

    /// @notice function used to get the amounts of token0 and token1 sitting
    /// on the position for a specific price.
    /// @param priceX96 price at which we want to simulate our tokens composition
    /// @return amount0 the amount of token0 sitting on the position for priceX96.
    /// @return amount1 the amount of token1 sitting on the position for priceX96.
    function totalUnderlyingAtPrice(uint160 priceX96) external view returns (uint256 amount0, uint256 amount1);

    /// @notice function used to get the initial amounts needed to open a position.
    /// @return init0 the amount of token0 needed to open a position.
    /// @return init1 the amount of token1 needed to open a position.
    function getInits() external view returns (uint256 init0, uint256 init1);

    /// @notice function used to get the address of token0.
    function token0() external view returns (address);

    /// @notice function used to get the address of token1.
    function token1() external view returns (address);

    /// @notice function used to get manager address.
    function manager() external view returns (address);

    /// @notice function used to get module used to
    /// open/close/manager a position.
    function module() external view returns (address);
}
