// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.26;

import {Clones} from '@openzeppelin/contracts/proxy/Clones.sol';
import {IVaultsRegistry} from '@stakewise-core/interfaces/IVaultsRegistry.sol';
import {Errors} from '@stakewise-core/libraries/Errors.sol';
import {ITokensConverterFactory} from './interfaces/ITokensConverterFactory.sol';
import {IBaseTokensConverter} from './interfaces/IBaseTokensConverter.sol';

/**
 * @title ITokensConverterFactory
 * @author StakeWise
 * @notice Factory for deploying TokensConverter contracts
 */
contract TokensConverterFactory is ITokensConverterFactory {
    IVaultsRegistry internal immutable _vaultsRegistry;

    /// @inheritdoc ITokensConverterFactory
    address public immutable implementation;

    /**
     * @dev Constructor
     * @param _implementation The implementation address of TokensConverter contract
     * @param vaultsRegistry The address of the VaultsRegistry contract
     */
    constructor(address _implementation, address vaultsRegistry) {
        implementation = _implementation;
        _vaultsRegistry = IVaultsRegistry(vaultsRegistry);
    }

    /// @inheritdoc ITokensConverterFactory
    function getTokensConverter(
        address vault
    ) public view returns (address converter) {
        // get the address of the converter
        converter = Clones.predictDeterministicAddress(implementation, bytes32(uint256(uint160(vault))));
    }

    /// @inheritdoc ITokensConverterFactory
    function createConverter(
        address vault
    ) external returns (address converter) {
        if (vault == address(0) || !_vaultsRegistry.vaults(vault)) {
            revert Errors.InvalidVault();
        }
        converter = Clones.cloneDeterministic(implementation, bytes32(uint256(uint160(vault))));

        // initialize converter
        IBaseTokensConverter(converter).initialize(vault);

        // emit event
        emit TokensConverterCreated(msg.sender, vault, converter);
    }
}
