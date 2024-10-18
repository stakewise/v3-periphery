// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.26;

import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';
import {IKeeperRewards} from '@stakewise-core/interfaces/IKeeperRewards.sol';
import {IVaultState} from '@stakewise-core/interfaces/IVaultState.sol';
import {IVaultOsToken} from '@stakewise-core/interfaces/IVaultOsToken.sol';
import {IOsTokenVaultController} from '@stakewise-core/interfaces/IOsTokenVaultController.sol';
import {IVaultUserLtvTracker} from './interfaces/IVaultUserLtvTracker.sol';

/**
 * @title VaultUserLtvTracker
 * @author StakeWise
 * @notice Stores user with a maximum LTV value for each vault
 */
contract VaultUserLtvTracker is IVaultUserLtvTracker {
    uint256 private constant _wad = 1e18;
    IKeeperRewards private immutable _keeperRewards;
    IOsTokenVaultController private immutable _osTokenVaultController;

    /**
     * @dev Constructor
     * @param keeper The address of the Keeper contract
     * @param osTokenVaultController The address of the OsTokenVaultController contract
     */
    constructor(address keeper, address osTokenVaultController) {
        _keeperRewards = IKeeperRewards(keeper);
        _osTokenVaultController = IOsTokenVaultController(osTokenVaultController);
    }

    // Mapping to store the user with the highest LTV for each vault
    mapping(address vault => address user) public vaultToUser;

    /// @inheritdoc IVaultUserLtvTracker
    function updateVaultMaxLtvUser(
        address vault,
        address newUser,
        IKeeperRewards.HarvestParams calldata harvestParams
    ) external {
        // Get the previous max LTV user for the vault
        address prevUser = vaultToUser[vault];

        if (newUser == prevUser) {
            return;
        }

        // Calculate the LTV for both users
        uint256 newLtv = _calculateLtv(vault, newUser, harvestParams);
        uint256 prevLtv = _calculateLtv(vault, prevUser, harvestParams);

        // If the new user has a higher LTV, update the record
        if (newLtv > prevLtv) {
            vaultToUser[vault] = newUser;
        }
    }

    /// @inheritdoc IVaultUserLtvTracker
    function getVaultMaxLtv(
        address vault,
        IKeeperRewards.HarvestParams calldata harvestParams
    ) external returns (uint256) {
        address user = vaultToUser[vault];

        // Calculate the latest LTV for the stored user
        return _calculateLtv(vault, user, harvestParams);
    }

    /**
     * @dev Internal function for calculating LTV
     * @param vault The address of the vault
     * @param user The address of the user
     * @param harvestParams The harvest params to use for updating the vault state
     */
    function _calculateLtv(
        address vault,
        address user,
        IKeeperRewards.HarvestParams calldata harvestParams
    ) private returns (uint256) {
        // Skip calculation for zero address
        if (user == address(0)) {
            return 0;
        }

        // Update vault state to get up-to-date value of user stake
        if (_keeperRewards.canHarvest(vault)) {
            IVaultState(vault).updateState(harvestParams);
        }

        // Get OsToken position
        uint256 osTokenShares = IVaultOsToken(vault).osTokenPositions(user);

        // Convert OsToken position to Wei
        uint256 osTokenAssets = _osTokenVaultController.convertToAssets(osTokenShares);

        if (osTokenAssets == 0) {
            return 0;
        }

        // Get user stake in a vault
        uint256 vaultShares = IVaultState(vault).getShares(user);

        // Convert user stake to Wei
        uint256 vaultAssets = IVaultState(vault).convertToAssets(vaultShares);

        if (vaultAssets == 0) {
            return 0;
        }

        // Calculate Loan-To-Value ratio
        return Math.mulDiv(osTokenAssets, _wad, vaultAssets);
    }
}
