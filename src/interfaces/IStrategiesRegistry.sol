// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.26;

/**
 * @title IStrategiesRegistry
 * @author StakeWise
 * @notice Defines the interface for the StrategiesRegistry contract
 */
interface IStrategiesRegistry {
    error InvalidStrategyId();

    /**
     * @notice Event emitted on a Strategy update
     * @param caller The address that called the function
     * @param strategy The address of the updated strategy
     * @param enabled The new status of the strategy
     */
    event StrategyUpdated(address indexed caller, address strategy, bool enabled);

    /**
     * @notice Event emitted on adding Strategy proxy contract
     * @param strategy The address of the Strategy that added the proxy
     * @param proxy The address of the added proxy
     */
    event StrategyProxyAdded(address indexed strategy, address indexed proxy);

    /**
     * @notice Event emitted on updating the strategy configuration
     * @param strategyId The ID of the strategy to update the configuration
     * @param configName The name of the configuration to update
     * @param value The new value of the configuration
     */
    event StrategyConfigUpdated(bytes32 indexed strategyId, string configName, bytes value);

    /**
     * @notice Registered Strategies
     * @param strategy The address of the strategy to check whether it is registered
     * @return `true` for the registered Strategy, `false` otherwise
     */
    function strategies(address strategy) external view returns (bool);

    /**
     * @notice Registered Strategy Proxies
     * @param proxy The address of the proxy to check whether it is registered
     * @return `true` for the registered Strategy proxy, `false` otherwise
     */
    function strategyProxies(address proxy) external view returns (bool);

    /**
     * @notice Get strategy configuration
     * @param strategyId The ID of the strategy to get the configuration
     * @param configName The name of the configuration
     * @return value The value of the configuration
     */
    function getStrategyConfig(
        bytes32 strategyId,
        string calldata configName
    ) external view returns (bytes memory value);

    /**
     * @notice Set strategy configuration. Can only be called by the owner.
     * @param strategyId The ID of the strategy to set the configuration
     * @param configName The name of the configuration
     * @param value The value of the configuration
     */
    function setStrategyConfig(bytes32 strategyId, string calldata configName, bytes calldata value) external;

    /**
     * @notice Function for enabling/disabling the Strategy. Can only be called by the owner.
     * @param strategy The address of the strategy to enable/disable
     * @param enabled The new status of the strategy
     */
    function setStrategy(address strategy, bool enabled) external;

    /**
     * @notice Function for adding Strategy proxy contract. Can only be called by the registered strategy.
     * @param proxy The address of the proxy to add
     */
    function addStrategyProxy(address proxy) external;

    /**
     * @notice Function for initializing the registry. Can only be called once during the deployment.
     * @param _owner The address of the owner of the contract
     */
    function initialize(address _owner) external;
}
