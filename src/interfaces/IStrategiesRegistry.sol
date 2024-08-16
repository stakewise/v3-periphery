// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.26;

/**
 * @title IStrategiesRegistry
 * @author StakeWise
 * @notice Defines the interface for the StrategiesRegistry
 */
interface IStrategiesRegistry {
    /**
     * @notice Event emitted on a Strategy addition
     * @param caller The address that has added the Strategy
     * @param strategy The address of the added strategy
     */
    event StrategyAdded(address indexed caller, address indexed strategy);

    /**
     * @notice Event emitted on adding Strategy implementation contract
     * @param impl The address of the new implementation contract
     */
    event StrategyImplAdded(address indexed impl);

    /**
     * @notice Event emitted on removing Strategy implementation contract
     * @param impl The address of the removed implementation contract
     */
    event StrategyImplRemoved(address indexed impl);

    /**
     * @notice Event emitted on whitelisting the factory
     * @param factory The address of the whitelisted factory
     */
    event FactoryAdded(address indexed factory);

    /**
     * @notice Event emitted on removing the factory from the whitelist
     * @param factory The address of the factory removed from the whitelist
     */
    event FactoryRemoved(address indexed factory);

    /**
     * @notice Event emitted on setting the maximum LTV percent for the vault to mint osTokens
     * @param newVaultMaxLtvPercent The maximum leverage ratio in 1e18 precision
     */
    event VaultMaxLtvPercentUpdated(uint256 newVaultMaxLtvPercent);

    /**
     * @notice Registered Strategies
     * @param strategy The address of the strategy to check whether it is registered
     * @return `true` for the registered Strategy, `false` otherwise
     */
    function strategies(address strategy) external view returns (bool);

    /**
     * @notice Maximum LTV percent for the vault to mint osTokens
     * @return The maximum leverage ratio in 1e18 precision
     */
    function vaultMaxLtvPercent() external view returns (uint256);

    /**
     * @notice Registered Strategy implementations
     * @param impl The address of the strategy implementation
     * @return `true` for the registered implementation, `false` otherwise
     */
    function strategyImpls(address impl) external view returns (bool);

    /**
     * @notice Registered Factories
     * @param factory The address of the factory to check whether it is whitelisted
     * @return `true` for the whitelisted Factory, `false` otherwise
     */
    function factories(address factory) external view returns (bool);

    /**
     * @notice Function for adding Strategy to the registry. Can only be called by the whitelisted Factory.
     * @param strategy The address of the Strategy to add
     */
    function addStrategy(address strategy) external;

    /**
     * @notice Function for adding Strategy implementation contract
     * @param newImpl The address of the new implementation contract
     */
    function addStrategyImpl(address newImpl) external;

    /**
     * @notice Function for removing Strategy implementation contract
     * @param impl The address of the removed implementation contract
     */
    function removeStrategyImpl(address impl) external;

    /**
     * @notice Function for adding the factory to the whitelist
     * @param factory The address of the factory to add to the whitelist
     */
    function addFactory(address factory) external;

    /**
     * @notice Function for removing the factory from the whitelist
     * @param factory The address of the factory to remove from the whitelist
     */
    function removeFactory(address factory) external;

    /**
     * @notice Function for setting the maximum LTV percent for the vault to mint osTokens. Can only be called by the owner.
     * @param _vaultMaxLtvPercent The maximum leverage ratio in 1e18 precision
     */
    function setVaultMaxLtvPercent(uint256 _vaultMaxLtvPercent) external;

    /**
     * @notice Function for initializing the registry. Can only be called once during the deployment.
     * @param _owner The address of the owner of the contract
     */
    function initialize(address _owner) external;
}
