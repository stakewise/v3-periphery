// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.26;

import {IFlashLoanRecipient} from './IFlashLoanRecipient.sol';

/**
 * @title IOsTokenVaultEscrow
 * @author StakeWise
 * @notice Interface for OsTokenVaultEscrow contract
 */
interface ILeverageStrategy is IFlashLoanRecipient {
    error InvalidFlashloanAction();
    error InvalidExitQueuePercent();
    error InvalidExitPositionTickets();

    /**
     * @notice Enum for flashloan actions
     * @param Deposit Deposit assets
     * @param ClaimExitedAssets Claim exited assets
     */
    enum FlashloanAction {
        Deposit,
        ClaimExitedAssets
    }

    /**
     * @notice Struct to store the exit position details
     * @param positionTicket The exit position ticket
     * @param osTokenShares The amount of osToken shares to burn
     */
    struct ExitPosition {
        uint256 positionTicket;
        uint256 osTokenShares;
    }

    /**
     * @notice Deposit assets to the strategy
     * @param osTokenShares Amount of osToken shares to deposit
     * @param assets Amount of assets leveraged
     */
    event Deposited(uint256 osTokenShares, uint256 assets);

    /**
     * @notice Enter the OsToken escrow exit queue
     * @param positionPercent Percent of the position to exit from strategy
     * @param exitQueueShares Amount of osToken shares to transfer to the escrow
     */
    event ExitQueueEntered(uint256 positionPercent, uint256 exitQueueShares);

    /**
     * @notice Processes exited assets
     * @param exitPositionTickets The exit position tickets
     * @param timestamps The timestamps of the exit position tickets
     */
    event ExitedAssetsProcessed(uint256[] exitPositionTickets, uint256[] timestamps);

    /**
     * @notice Claim exited assets
     * @param osTokenShares The amount of osToken shares claimed by the user
     * @param assets The amount of assets claimed by the user
     */
    event ExitedAssetsClaimed(uint256 osTokenShares, uint256 assets);

    /**
     * @notice Address of the vault
     * @return The address of the vault
     */
    function vault() external view returns (address);

    /**
     * @notice Strategy Unique Identifier
     * @return The unique identifier of the strategy
     */
    function strategyId() external pure returns (bytes32);

    /**
     * @notice Version
     * @return The version of the Strategy implementation contract
     */
    function version() external pure returns (uint8);

    /**
     * @notice Implementation
     * @return The address of the Strategy implementation contract
     */
    function implementation() external view returns (address);

    /**
     * @notice Initializes the strategy
     * @param params The initialization parameters
     */
    function initialize(bytes calldata params) external;

    /**
     * @notice Approves the osToken transfers from the user to the strategy
     * @param osTokenShares Amount of osToken shares to approve
     * @param deadline Unix timestamp after which the transaction will revert
     * @param v ECDSA signature v
     * @param r ECDSA signature r
     * @param s ECDSA signature s
     */
    function permit(uint256 osTokenShares, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external;

    /**
     * @notice Deposit assets to the strategy
     * @param osTokenShares Amount of osToken shares to deposit
     */
    function deposit(uint256 osTokenShares) external;

    /**
     * @notice Enter the OsToken escrow exit queue
     * @param positionPercent The percent of the position to exit from the strategy
     */
    function enterExitQueue(uint256 positionPercent) external;

    /**
     * @notice Processes exited assets
     * @param exitPositionTickets The exit position tickets
     * @param timestamps The timestamps of the exit position tickets
     */
    function processExitedAssets(uint256[] calldata exitPositionTickets, uint256[] calldata timestamps) external;

    /**
     * @notice Claim exited assets
     * @param exitPositionTickets The exit position tickets to claim the assets from
     */
    function claimExitedAssets(uint256[] calldata exitPositionTickets) external;

    /**
     * @notice Get the user assets in the strategy
     * @return The amount of osToken shares that belong to the user
     * @return assets The amount of assets that belong to the user
     */
    function getUserAssets() external view returns (uint256, uint256);
}
