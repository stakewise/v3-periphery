// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.26;

import {IKeeperRewards} from '@stakewise-core/interfaces/IKeeperRewards.sol';
import {IFlashLoanRecipient} from './IFlashLoanRecipient.sol';
import {IStrategy} from '../../interfaces/IStrategy.sol';

/**
 * @title ILeverageStrategy
 * @author StakeWise
 * @notice Interface for LeverageStrategy contract
 */
interface ILeverageStrategy is IFlashLoanRecipient, IStrategy {
    error InvalidFlashloanAction();
    error ExitQueueNotEntered();
    error InvalidExitQueuePercent();
    error InvalidExitQueueTicket();

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
     * @notice Struct to store the exit position
     * @param positionTicket The exit position ticket
     * @param timestamp The timestamp of the exit position
     * @param exitQueueIndex The index of the exit position in the processed queue
     */
    struct ExitPosition {
        uint256 positionTicket;
        uint256 timestamp;
        uint256 exitQueueIndex;
    }

    /**
     * @notice Event emitted when the strategy proxy is created
     * @param vault The address of the vault
     * @param user The address of the user
     * @param proxy The address of the proxy created
     */
    event StrategyProxyCreated(address indexed vault, address indexed user, address proxy);

    /**
     * @notice Deposit assets to the strategy
     * @param vault The address of the vault
     * @param user The address of the user
     * @param osTokenShares Amount of osToken shares to deposit
     * @param assets Amount of assets leveraged
     */
    event Deposited(address indexed vault, address indexed user, uint256 osTokenShares, uint256 assets);

    /**
     * @notice Enter the OsToken escrow exit queue
     * @param vault The address of the vault
     * @param user The address of the user
     * @param positionTicket The exit position ticket
     * @param timestamp The timestamp of the exit position ticket
     * @param osTokenShares The amount of osToken shares to exit
     */
    event ExitQueueEntered(
        address indexed vault, address indexed user, uint256 positionTicket, uint256 timestamp, uint256 osTokenShares
    );

    /**
     * @notice Claim exited assets
     * @param osTokenShares The amount of osToken shares claimed by the user
     * @param assets The amount of assets claimed by the user
     */
    event ExitedAssetsClaimed(address indexed vault, address indexed user, uint256 osTokenShares, uint256 assets);

    /**
     * @notice Event emitted when the strategy proxy is upgraded
     * @param vault The address of the vault
     * @param user The address of the user
     * @param strategy The address of the new strategy
     */
    event StrategyProxyUpgraded(address indexed vault, address indexed user, address strategy);

    /**
     * @notice Get the strategy proxy address
     * @param vault The address of the vault
     * @param user The address of the user
     * @return proxy The address of the strategy proxy
     */
    function getStrategyProxy(address vault, address user) external view returns (address proxy);

    /**
     * @notice Checks if the proxy is exiting
     * @param proxy The address of the proxy
     * @return isExiting True if the proxy is exiting
     */
    function isStrategyProxyExiting(address proxy) external view returns (bool isExiting);

    /**
     * @notice Updates the vault state
     * @param vault The address of the vault
     * @param harvestParams The harvest parameters
     */
    function updateVaultState(address vault, IKeeperRewards.HarvestParams calldata harvestParams) external;

    /**
     * @notice Approves the osToken transfers from the user to the strategy
     * @param vault The address of the vault
     * @param osTokenShares Amount of osToken shares to approve
     * @param deadline Unix timestamp after which the transaction will revert
     * @param v ECDSA signature v
     * @param r ECDSA signature r
     * @param s ECDSA signature s
     */
    function permit(address vault, uint256 osTokenShares, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external;

    /**
     * @notice Deposit assets to the strategy
     * @param vault The address of the vault
     * @param osTokenShares Amount of osToken shares to deposit
     */
    function deposit(address vault, uint256 osTokenShares) external;

    /**
     * @notice Enter the OsToken escrow exit queue. Can only be called by the position owner.
     * @param vault The address of the vault
     * @param positionPercent The percent of the position to exit from strategy
     * @return positionTicket The exit position ticket
     */
    function enterExitQueue(address vault, uint256 positionPercent) external returns (uint256 positionTicket);

    /**
     * @notice Force enter the OsToken escrow exit queue. Can be called by anyone if approaching liquidation.
     * @param vault The address of the vault
     * @param user The address of the user
     * @return positionTicket The exit position ticket
     */
    function forceEnterExitQueue(address vault, address user) external returns (uint256 positionTicket);

    /**
     * @notice Processes exited assets. Can be called by anyone.
     * @param vault The address of the vault
     * @param user The address of the user
     * @param exitPosition The exit position to process
     */
    function processExitedAssets(address vault, address user, ExitPosition calldata exitPosition) external;

    /**
     * @notice Claim exited assets. Can be called by anyone.
     * @param vault The address of the vault
     * @param user The address of the user
     * @param exitPositionTicket The exit position ticket to claim the assets
     */
    function claimExitedAssets(address vault, address user, uint256 exitPositionTicket) external;

    /**
     * @notice Upgrade the strategy proxy. Can only be called by the proxy owner.
     * @param vault The address of the vault
     */
    function upgradeProxy(address vault) external;
}
