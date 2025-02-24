// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.26;

import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/math/SafeCast.sol';
import {IOsTokenVaultController} from '@stakewise-core/interfaces/IOsTokenVaultController.sol';
import {IKeeperRewards} from '@stakewise-core/interfaces/IKeeperRewards.sol';
import {IVaultState} from '@stakewise-core/interfaces/IVaultState.sol';
import {IOsTokenVaultEscrow} from '@stakewise-core/interfaces/IOsTokenVaultEscrow.sol';
import {IVaultEnterExit} from '@stakewise-core/interfaces/IVaultEnterExit.sol';
import {Errors} from '@stakewise-core/libraries/Errors.sol';
import {ILeverageStrategy} from './leverage/interfaces/ILeverageStrategy.sol';
import {IBoostHelpers} from './interfaces/IBoostHelpers.sol';

/**
 * @title BoostHelpers
 * @author StakeWise
 * @notice Defines the helper method to fetch the boost position details
 */
contract BoostHelpers is IBoostHelpers {
    uint256 private constant _wad = 1e18;

    IKeeperRewards private immutable _keeper;
    ILeverageStrategy private immutable _leverageStrategy;
    IOsTokenVaultController private immutable _osTokenCtrl;
    IOsTokenVaultEscrow private immutable _osTokenEscrow;

    /**
     * @dev Constructor
     * @param keeper The address of the Keeper contract
     * @param leverageStrategy The address of the LeverageStrategy contract
     * @param osTokenCtrl The address of the OsTokenVaultController contract
     * @param osTokenEscrow The address of the OsTokenVaultEscrow contract
     */
    constructor(address keeper, address leverageStrategy, address osTokenCtrl, address osTokenEscrow) {
        _keeper = IKeeperRewards(keeper);
        _leverageStrategy = ILeverageStrategy(leverageStrategy);
        _osTokenCtrl = IOsTokenVaultController(osTokenCtrl);
        _osTokenEscrow = IOsTokenVaultEscrow(osTokenEscrow);
    }

    /// @inheritdoc IBoostHelpers
    function getBoostOsTokenShares(
        address user,
        address vault,
        IKeeperRewards.HarvestParams calldata harvestParams,
        ExitRequest calldata exitRequest
    ) external returns (uint256) {
        BoostDetails memory boost = _calculateBoost(user, vault, harvestParams, exitRequest);
        return boost.osTokenShares + _osTokenCtrl.convertToShares(boost.assets);
    }

    /// @inheritdoc IBoostHelpers
    function getBoostDetails(
        address user,
        address vault,
        IKeeperRewards.HarvestParams calldata harvestParams,
        ExitRequest calldata exitRequest
    ) external returns (BoostDetails memory) {
        return _calculateBoost(user, vault, harvestParams, exitRequest);
    }

    /**
     * @dev Calculate the boost details
     * @param user The address of the user
     * @param vault The address of the vault
     * @param harvestParams The harvest parameters to update the vault state if needed.
     * @param exitRequest The exit request details if there is an exiting position.
     * @return boost The boost details
     */
    function _calculateBoost(
        address user,
        address vault,
        IKeeperRewards.HarvestParams calldata harvestParams,
        ExitRequest calldata exitRequest
    ) private returns (BoostDetails memory boost) {
        if (_keeper.canHarvest(vault)) {
            IVaultState(vault).updateState(harvestParams);
        }
        address proxy = _leverageStrategy.getStrategyProxy(vault, user);
        (uint256 borrowedAssets, uint256 suppliedOsTokenShares) = _leverageStrategy.getBorrowState(proxy);
        (uint256 stakedAssets, uint256 mintedOsTokenShares) = _leverageStrategy.getVaultState(vault, proxy);

        (uint256 exitingOsTokenShares, uint256 exitingAssets) = _getExitRequestState(vault, proxy, exitRequest);
        mintedOsTokenShares += exitingOsTokenShares;
        stakedAssets += exitingAssets;

        if (borrowedAssets >= stakedAssets) {
            uint256 leftOsTokenAssets =
                Math.mulDiv(borrowedAssets - stakedAssets, _wad, _leverageStrategy.getBorrowLtv());
            int256 _osTokenShares = SafeCast.toInt256(suppliedOsTokenShares) - SafeCast.toInt256(mintedOsTokenShares)
                - SafeCast.toInt256(_osTokenCtrl.convertToShares(leftOsTokenAssets));
            boost.osTokenShares = _osTokenShares < 0 ? 0 : SafeCast.toUint256(_osTokenShares);
        } else {
            boost.osTokenShares = suppliedOsTokenShares - mintedOsTokenShares;
            int256 _assets = SafeCast.toInt256(stakedAssets) - SafeCast.toInt256(borrowedAssets);
            boost.assets = _assets < 0 ? 0 : SafeCast.toUint256(_assets);
        }
        boost.osTokenLtv = Math.mulDiv(_osTokenCtrl.convertToAssets(mintedOsTokenShares), _wad, stakedAssets);
        boost.borrowLtv = Math.mulDiv(borrowedAssets, _wad, _osTokenCtrl.convertToAssets(suppliedOsTokenShares));
    }

    /**
     * @dev Get the exit request state
     * @param vault The address of the vault
     * @param proxy The address of the strategy proxy
     * @param exitRequest The exit request details
     * @return osTokenShares The amount of osToken shares exiting
     * @return assets The amount of assets exiting
     */
    function _getExitRequestState(
        address vault,
        address proxy,
        ExitRequest calldata exitRequest
    ) private view returns (uint256 osTokenShares, uint256 assets) {
        if (!_leverageStrategy.isStrategyProxyExiting(proxy)) {
            return (0, 0);
        }

        address owner;
        uint256 exitedAssets;
        (owner, exitedAssets, osTokenShares) = _osTokenEscrow.getPosition(vault, exitRequest.positionTicket);
        if (owner != proxy) {
            revert Errors.InvalidPosition();
        } else if (osTokenShares <= 1) {
            return (0, 0);
        } else if (exitedAssets > 0) {
            return (osTokenShares, exitedAssets);
        }

        int256 _exitQueueIndex = IVaultEnterExit(vault).getExitQueueIndex(exitRequest.positionTicket);
        uint256 exitQueueIndex = _exitQueueIndex < 0 ? type(uint256).max : SafeCast.toUint256(_exitQueueIndex);

        uint256 leftTickets;
        uint256 exitedTickets;
        (leftTickets, exitedTickets, exitedAssets) = IVaultEnterExit(vault).calculateExitedAssets(
            address(_osTokenEscrow), exitRequest.positionTicket, exitRequest.timestamp, exitQueueIndex
        );
        assets = exitedAssets + IVaultState(vault).convertToAssets(leftTickets);
    }
}
