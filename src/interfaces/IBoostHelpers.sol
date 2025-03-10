// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.26;

import {IKeeperRewards} from '@stakewise-core/interfaces/IKeeperRewards.sol';

/**
 * @title IBoostHelpers
 * @author StakeWise
 * @notice Defines the interface for the BoostHelpers contract
 */
interface IBoostHelpers {
    /**
     * @notice Struct to store the exit request details
     * @param positionTicket The exit queue ticket that was assigned to the position
     * @param timestamp The timestamp of the exit request
     */
    struct ExitRequest {
        uint256 positionTicket;
        uint256 timestamp;
    }

    /**
     * @notice Struct to store the boost details
     * @param osTokenShares The amount of osToken shares
     * @param assets The amount of assets
     * @param borrowLtv The borrow LTV
     * @param osTokenLtv The osToken minting LTV
     */
    struct BoostDetails {
        uint256 osTokenShares;
        uint256 assets;
        uint256 borrowLtv;
        uint256 osTokenLtv;
    }

    /**
     * @notice Calculate the osToken shares in boost
     * @param user The address of the user
     * @param vault The address of the vault
     * @param harvestParams The harvest parameters to update the vault state if needed.
     * @param exitRequest The exit request details if there is an exiting position.
     * @return osTokenShares The amount of osToken shares boosted
     */
    function getBoostOsTokenShares(
        address user,
        address vault,
        IKeeperRewards.HarvestParams memory harvestParams,
        ExitRequest calldata exitRequest
    ) external returns (uint256 osTokenShares);

    /**
     * @notice Calculate the boost details
     * @param user The address of the user
     * @param vault The address of the vault
     * @param harvestParams The harvest parameters to update the vault state if needed.
     * @param exitRequest The exit request details if there is an exiting position.
     * @return boost The boost details
     */
    function getBoostDetails(
        address user,
        address vault,
        IKeeperRewards.HarvestParams memory harvestParams,
        ExitRequest calldata exitRequest
    ) external returns (BoostDetails memory);
}
