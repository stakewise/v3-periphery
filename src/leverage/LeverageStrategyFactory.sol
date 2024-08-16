// SPDX-License-Identifier: AGPL-1.1

pragma solidity ^0.8.26;

import {ERC1967Proxy} from '@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol';
import {IVaultsRegistry} from '@stakewise-core/interfaces/IVaultsRegistry.sol';
import {Errors} from '@stakewise-core/libraries/Errors.sol';
import {IStrategiesRegistry} from '../interfaces/IStrategiesRegistry.sol';
import {ILeverageStrategy} from './interfaces/ILeverageStrategy.sol';
import {ILeverageStrategyFactory, IStrategyFactory} from './interfaces/ILeverageStrategyFactory.sol';

/**
 * @title LeverageStrategyFactory
 * @author StakeWise
 * @notice Factory for deploying leverage strategies
 */
contract LeverageStrategyFactory is ILeverageStrategyFactory {
    IStrategiesRegistry private immutable _strategiesRegistry;
    IVaultsRegistry private immutable _vaultsRegistry;

    /// @inheritdoc IStrategyFactory
    address public immutable implementation;

    /**
     * @dev Constructor
     * @param _implementation The implementation address of Strategy
     * @param vaultsRegistry The address of the VaultsRegistry contract
     * @param strategiesRegistry The address of the StrategiesRegistry contract
     */
    constructor(address _implementation, address vaultsRegistry, address strategiesRegistry) {
        implementation = _implementation;
        _vaultsRegistry = IVaultsRegistry(vaultsRegistry);
        _strategiesRegistry = IStrategiesRegistry(strategiesRegistry);
    }

    /// @inheritdoc ILeverageStrategyFactory
    function createStrategy(address vault) external returns (address strategy) {
        if (!_vaultsRegistry.vaults(vault)) revert Errors.InvalidVault();

        // create strategy proxy
        strategy = address(new ERC1967Proxy(implementation, ''));

        // initialize Vault
        ILeverageStrategy(strategy).initialize(abi.encode(vault, msg.sender));

        // add vault to the registry
        _strategiesRegistry.addStrategy(vault);

        // emit event
        emit LeverageStrategyCreated(strategy, msg.sender, vault);
    }
}
