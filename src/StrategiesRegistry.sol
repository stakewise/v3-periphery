// SPDX-License-Identifier: AGPL-1.1

pragma solidity ^0.8.26;

import {Ownable2Step, Ownable} from '@openzeppelin/contracts/access/Ownable2Step.sol';
import {Errors} from '@stakewise-core/libraries/Errors.sol';
import {IStrategiesRegistry} from './interfaces/IStrategiesRegistry.sol';

/**
 * @title StrategiesRegistry
 * @author StakeWise
 * @notice Defines the registry functionality that keeps track of Strategies, Factories and Strategy upgrades
 */
contract StrategiesRegistry is Ownable2Step, IStrategiesRegistry {
    uint256 private constant _maxPercent = 1e18;

    /// @inheritdoc IStrategiesRegistry
    mapping(address => bool) public strategies;

    /// @inheritdoc IStrategiesRegistry
    mapping(address => bool) public factories;

    /// @inheritdoc IStrategiesRegistry
    mapping(address => bool) public strategyImpls;

    /// @inheritdoc IStrategiesRegistry
    uint256 public vaultMaxLtvPercent;

    bool private _initialized;

    /**
     * @dev Constructor
     */
    constructor() Ownable(msg.sender) {}

    /// @inheritdoc IStrategiesRegistry
    function addStrategy(address strategy) external {
        if (!factories[msg.sender] && msg.sender != owner()) revert Errors.AccessDenied();

        strategies[strategy] = true;
        emit StrategyAdded(msg.sender, strategy);
    }

    /// @inheritdoc IStrategiesRegistry
    function addStrategyImpl(address newImpl) external onlyOwner {
        if (strategyImpls[newImpl]) revert Errors.AlreadyAdded();
        strategyImpls[newImpl] = true;
        emit StrategyImplAdded(newImpl);
    }

    /// @inheritdoc IStrategiesRegistry
    function removeStrategyImpl(address impl) external onlyOwner {
        if (!strategyImpls[impl]) revert Errors.AlreadyRemoved();
        strategyImpls[impl] = false;
        emit StrategyImplRemoved(impl);
    }

    /// @inheritdoc IStrategiesRegistry
    function addFactory(address factory) external onlyOwner {
        if (factories[factory]) revert Errors.AlreadyAdded();
        factories[factory] = true;
        emit FactoryAdded(factory);
    }

    /// @inheritdoc IStrategiesRegistry
    function removeFactory(address factory) external onlyOwner {
        if (!factories[factory]) revert Errors.AlreadyRemoved();
        factories[factory] = false;
        emit FactoryRemoved(factory);
    }

    /// @inheritdoc IStrategiesRegistry
    function setVaultMaxLtvPercent(uint256 _vaultMaxLtvPercent) external onlyOwner {
        // validate loan-to-value percent
        if (_vaultMaxLtvPercent == 0 || _vaultMaxLtvPercent > _maxPercent) {
            revert Errors.InvalidLtvPercent();
        }

        // emit event
        emit VaultMaxLtvPercentUpdated(_vaultMaxLtvPercent);
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
