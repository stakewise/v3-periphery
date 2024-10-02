// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.26;

import {IKeeperRewards} from '@stakewise-core/interfaces/IKeeperRewards.sol';

/**
 * @title IVaultUserLtvTracker
 * @author StakeWise
 * @notice Defines the interface for the VaultUserLtvTracker contract
 */
interface IVaultUserLtvTracker {
    /**
     * @notice Updates the vault's max LTV user
     * @param vault The address of the vault
     * @param user The address of the user
     * @param harvestParams The harvest params to use for updating the vault state
     */
    function updateVaultMaxLtvUser(
        address vault,
        address user,
        IKeeperRewards.HarvestParams calldata harvestParams
    ) external;

    /**
     * @notice Gets the current highest LTV for the vault
     * @param vault The address of the vault
     * @param harvestParams The harvest params to use for updating the vault state
     * @return The current highest LTV for the vault
     */
    function getVaultMaxLtv(
        address vault,
        IKeeperRewards.HarvestParams calldata harvestParams
    ) external returns (uint256);
}
