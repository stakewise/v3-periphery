// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.26;

import {Ownable2Step, Ownable} from '@openzeppelin/contracts/access/Ownable2Step.sol';
import {Errors} from '@stakewise-core/libraries/Errors.sol';
import {IStrategiesRegistry} from './interfaces/IStrategiesRegistry.sol';
import {IStrategy} from './interfaces/IStrategy.sol';

/**
 * @title StrategiesRegistry
 * @author StakeWise
 * @notice Defines the registry functionality that keeps track of Strategies and their settings
 */
contract StrategiesRegistry is Ownable2Step, IStrategiesRegistry {
    uint256 private constant _maxPercent = 1e18;

    /// @inheritdoc IStrategiesRegistry
    mapping(address strategy => bool enabled) public strategies;

    /// @inheritdoc IStrategiesRegistry
    mapping(bytes32 strategyProxyId => address proxy) public strategyProxyIdToProxy;

    /// @inheritdoc IStrategiesRegistry
    mapping(address proxy => bool exists) public strategyProxies;

    mapping(bytes32 strategyConfigId => bytes value) private _strategyConfigs;

    bool private _initialized;

    /**
     * @dev Constructor
     */
    constructor() Ownable(msg.sender) {}

    /// @inheritdoc IStrategiesRegistry
    function getStrategyConfig(
        bytes32 strategyId,
        string calldata configName
    ) external view returns (bytes memory value) {
        return _strategyConfigs[keccak256(abi.encode(strategyId, configName))];
    }

    /// @inheritdoc IStrategiesRegistry
    function setStrategy(address strategy, bool enabled) external onlyOwner {
        if (strategy == address(0)) revert Errors.ZeroAddress();
        if (strategies[strategy] == enabled) revert Errors.ValueNotChanged();
        // update strategy
        strategies[strategy] = enabled;
        emit StrategyUpdated(msg.sender, strategy, enabled);
    }

    /// @inheritdoc IStrategiesRegistry
    function addStrategyProxy(bytes32 strategyProxyId, address proxy) external {
        if (strategyProxyId == bytes32(0)) revert InvalidStrategyProxyId();
        if (proxy == address(0)) revert Errors.ZeroAddress();

        // only active strategies can add proxies
        if (!strategies[msg.sender]) revert Errors.AccessDenied();
        if (strategyProxies[proxy]) revert Errors.AlreadyAdded();

        // add strategy proxy
        strategyProxyIdToProxy[strategyProxyId] = proxy;
        strategyProxies[proxy] = true;
        emit StrategyProxyAdded(msg.sender, strategyProxyId, proxy);
    }

    /// @inheritdoc IStrategiesRegistry
    function setStrategyConfig(
        bytes32 strategyId,
        string calldata configName,
        bytes calldata value
    ) external onlyOwner {
        // calculate strategy config ID
        bytes32 strategyConfigId = keccak256(abi.encode(strategyId, configName));

        // update strategy config
        _strategyConfigs[strategyConfigId] = value;
        emit StrategyConfigUpdated(strategyId, configName, value);
    }

    /// @inheritdoc IStrategiesRegistry
    function initialize(address _owner) external onlyOwner {
        if (_owner == address(0)) revert Errors.ZeroAddress();
        if (_initialized) revert Errors.AccessDenied();

        // transfer ownership
        _transferOwnership(_owner);
        _initialized = true;
    }
}
