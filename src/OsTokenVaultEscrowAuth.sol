// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.26;

import {IOsTokenVaultEscrowAuth} from '@stakewise-core/interfaces/IOsTokenVaultEscrowAuth.sol';
import {IVaultsRegistry} from '@stakewise-core/interfaces/IVaultsRegistry.sol';
import {IVaultVersion} from '@stakewise-core/interfaces/IVaultVersion.sol';
import {IStrategiesRegistry} from './interfaces/IStrategiesRegistry.sol';

/**
 * @title OsTokenVaultEscrowAuth
 * @author StakeWise
 * @notice Defines the check whether the caller can register the exit position in the OsTokenVaultEscrow contract
 */
contract OsTokenVaultEscrowAuth is IOsTokenVaultEscrowAuth {
    IVaultsRegistry private immutable _vaultsRegistry;
    IStrategiesRegistry private immutable _strategiesRegistry;

    /**
     * @dev Constructor
     * @param vaultsRegistry The address of the VaultsRegistry contract
     * @param strategiesRegistry The address of the StrategiesRegistry contract
     */
    constructor(address vaultsRegistry, address strategiesRegistry) {
        _vaultsRegistry = IVaultsRegistry(vaultsRegistry);
        _strategiesRegistry = IStrategiesRegistry(strategiesRegistry);
    }

    /// @inheritdoc IOsTokenVaultEscrowAuth
    function canRegister(address vault, address owner, uint256, uint256) external view returns (bool) {
        return _vaultsRegistry.vaults(vault) && IVaultVersion(vault).version() > 2
            && _strategiesRegistry.strategyProxies(owner);
    }
}
