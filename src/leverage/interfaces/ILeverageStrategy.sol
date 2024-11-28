// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.26;

import {IKeeperRewards} from '@stakewise-core/interfaces/IKeeperRewards.sol';
import {IOsTokenFlashLoanRecipient} from '@stakewise-core/interfaces/IOsTokenFlashLoanRecipient.sol';
import {IStrategy} from '../../interfaces/IStrategy.sol';

/**
 * @title ILeverageStrategy
 * @author StakeWise
 * @notice Interface for LeverageStrategy contract
 */
interface ILeverageStrategy is IOsTokenFlashLoanRecipient, IStrategy {
    error InvalidFlashloanAction();
    error InvalidMaxSlippagePercent();
    error ExitQueueNotEntered();
    error InvalidExitQueuePercent();
    error InvalidExitQueueTicket();
    error InvalidBalancerPoolId();

    /**
     * @notice Enum for flashloan actions
     * @param Deposit Deposit assets
     * @param ClaimExitedAssets Claim exited assets
     * @param RescueVaultAssets Rescue vault assets
     * @param RescueLendingAssets Rescue lending assets
     */
    enum FlashloanAction {
        Deposit,
        ClaimExitedAssets,
        RescueVaultAssets,
        RescueLendingAssets
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
     * @param strategyProxyId The id of the strategy proxy
     * @param vault The address of the vault
     * @param user The address of the user
     * @param proxy The address of the proxy created
     */
    event StrategyProxyCreated(
        bytes32 indexed strategyProxyId, address indexed vault, address indexed user, address proxy
    );

    /**
     * @notice Deposit assets to the strategy
     * @param vault The address of the vault
     * @param user The address of the user
     * @param osTokenShares Amount of osToken shares to deposit
     * @param leverageOsTokenShares Amount of osToken shares leveraged
     * @param referrer The address of the referrer
     */
    event Deposited(
        address indexed vault,
        address indexed user,
        uint256 osTokenShares,
        uint256 leverageOsTokenShares,
        address referrer
    );

    /**
     * @notice Enter the OsToken escrow exit queue
     * @param vault The address of the vault
     * @param user The address of the user
     * @param positionTicket The exit position ticket
     * @param timestamp The timestamp of the exit position ticket
     * @param osTokenShares The amount of osToken shares to exit
     * @param positionPercent The percent of the position that is exiting from strategy
     */
    event ExitQueueEntered(
        address indexed vault,
        address indexed user,
        uint256 positionTicket,
        uint256 timestamp,
        uint256 osTokenShares,
        uint256 positionPercent
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
     * @notice Event emitted when the vault assets are rescued
     * @param vault The address of the vault
     * @param user The address of the user
     * @param osTokenShares The amount of osToken shares rescued
     * @param assets The amount of assets rescued
     */
    event VaultAssetsRescued(address indexed vault, address indexed user, uint256 osTokenShares, uint256 assets);

    /**
     * @notice Event emitted when the lending assets are rescued
     * @param vault The address of the vault
     * @param user The address of the user
     * @param osTokenShares The amount of osToken shares rescued
     * @param assets The amount of assets rescued
     */
    event LendingAssetsRescued(address indexed vault, address indexed user, uint256 osTokenShares, uint256 assets);

    /**
     * @notice Get the strategy proxy address
     * @param vault The address of the vault
     * @param user The address of the user
     * @return proxy The address of the strategy proxy
     */
    function getStrategyProxy(address vault, address user) external view returns (address proxy);

    /**
     * @notice Returns the vault LTV.
     * @param vault The address of the vault
     * @return The vault LTV
     */
    function getVaultLtv(
        address vault
    ) external view returns (uint256);

    /**
     * @notice Returns the borrow LTV.
     * @return The borrow LTV
     */
    function getBorrowLtv() external view returns (uint256);

    /**
     * @notice Returns the borrow position state for the proxy
     * @param proxy The address of the strategy proxy
     * @return borrowedAssets The amount of borrowed assets
     * @return suppliedOsTokenShares The amount of supplied osToken shares
     */
    function getBorrowState(
        address proxy
    ) external view returns (uint256 borrowedAssets, uint256 suppliedOsTokenShares);

    /**
     * @notice Returns the vault position state for the proxy
     * @param vault The address of the vault
     * @param proxy The address of the strategy proxy
     * @return stakedAssets The amount of staked assets
     * @return mintedOsTokenShares The amount of minted osToken shares
     */
    function getVaultState(
        address vault,
        address proxy
    ) external view returns (uint256 stakedAssets, uint256 mintedOsTokenShares);

    /**
     * @dev Checks whether the user can be forced to the exit queue
     * @param vault The address of the vault
     * @param user The address of the user
     * @return True if the user can be forced to the exit queue, otherwise false
     */
    function canForceEnterExitQueue(address vault, address user) external view returns (bool);

    /**
     * @notice Checks if the proxy is exiting
     * @param proxy The address of the proxy
     * @return isExiting True if the proxy is exiting
     */
    function isStrategyProxyExiting(
        address proxy
    ) external view returns (bool isExiting);

    /**
     * @notice Calculates the amount of osToken shares to flashloan
     * @param vault The address of the vault
     * @param osTokenShares The amount of osToken shares at hand
     * @return The amount of osToken shares to flashloan
     */
    function getFlashloanOsTokenShares(address vault, uint256 osTokenShares) external view returns (uint256);

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
     * @param referrer The address of the referrer
     */
    function deposit(address vault, uint256 osTokenShares, address referrer) external;

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
     * @notice Claim exited assets. Can be called by anyone.
     * @param vault The address of the vault
     * @param user The address of the user
     * @param exitPosition The exit position to process
     */
    function claimExitedAssets(address vault, address user, ExitPosition calldata exitPosition) external;

    /**
     * @notice Rescue vault assets. Can only be called by the position owner to rescue the vault assets in case of lending protocol liquidation.
     * @param vault The address of the vault
     * @param exitPosition The exit position to process
     */
    function rescueVaultAssets(address vault, ExitPosition calldata exitPosition) external;

    /**
     * @notice Rescue lending assets. Can only be called by the position owner to rescue the lending assets in case of vault liquidation.
     * @param vault The address of the vault
     * @param assets The amount of assets to repay
     * @param maxSlippagePercent The maximum slippage percent
     */
    function rescueLendingAssets(address vault, uint256 assets, uint256 maxSlippagePercent) external;

    /**
     * @notice Upgrade the strategy proxy. Can only be called by the proxy owner.
     * @param vault The address of the vault
     */
    function upgradeProxy(
        address vault
    ) external;
}
