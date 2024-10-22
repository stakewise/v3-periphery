// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.26;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';
import {IOsTokenConfig as IOsTokenConfigV2} from '@stakewise-core/interfaces/IOsTokenConfig.sol';
import {IOsTokenVaultController} from '@stakewise-core/interfaces/IOsTokenVaultController.sol';
import {IKeeperRewards} from '@stakewise-core/interfaces/IKeeperRewards.sol';
import {IVaultState} from '@stakewise-core/interfaces/IVaultState.sol';
import {IVaultVersion} from '@stakewise-core/interfaces/IVaultVersion.sol';
import {IVaultOsToken} from '@stakewise-core/interfaces/IVaultOsToken.sol';
import {Multicall} from '@stakewise-core/base/Multicall.sol';

interface IOsTokenConfigV1 {
    function ltvPercent() external view returns (uint256);
}

contract StakeHelpers is Multicall {
    struct StakeInput {
        address vault;
        address user;
        uint256 stakeAssets;
        IKeeperRewards.HarvestParams harvestParams;
    }

    struct StakeOutput {
        uint256 receivedOsTokenShares;
        uint256 exchangeRate;
    }

    struct UnstakeInput {
        address vault;
        address user;
        uint256 osTokenShares;
        IKeeperRewards.HarvestParams harvestParams;
    }

    struct UnstakeOutput {
        uint256 burnOsTokenShares;
        uint256 exitQueueShares;
        uint256 receivedAssets;
    }

    struct BalanceInput {
        address vault;
        address user;
        uint256 osTokenShares;
        IKeeperRewards.HarvestParams harvestParams;
    }

    uint256 private constant _maxPercent = 1e18;

    IKeeperRewards private immutable _keeper;
    IOsTokenConfigV1 private immutable _osTokenConfigV1;
    IOsTokenConfigV2 private immutable _osTokenConfigV2;
    IOsTokenVaultController private immutable _osTokenController;

    constructor(address keeper, address osTokenConfigV1, address osTokenConfigV2, address osTokenController) {
        _keeper = IKeeperRewards(keeper);
        _osTokenConfigV1 = IOsTokenConfigV1(osTokenConfigV1);
        _osTokenConfigV2 = IOsTokenConfigV2(osTokenConfigV2);
        _osTokenController = IOsTokenVaultController(osTokenController);
    }

    function calculateStake(
        StakeInput memory inputData
    ) external returns (StakeOutput memory outputData) {
        // check whether state can be updated
        if (_keeper.canHarvest(inputData.vault)) {
            IVaultState(inputData.vault).updateState(inputData.harvestParams);
        }

        // get vault LTV config
        uint256 vaultLtvPercent = _getVaultLtvPercent(inputData.vault);
        outputData.exchangeRate = _osTokenController.convertToShares(Math.mulDiv(1 ether, vaultLtvPercent, _maxPercent));

        // fetch user total staked assets and shares
        uint256 userStakeShares = IVaultState(inputData.vault).getShares(inputData.user);
        uint256 userStakeAssets = IVaultState(inputData.vault).convertToAssets(userStakeShares);
        userStakeAssets += inputData.stakeAssets;

        // fetch user osToken assets and shares
        uint256 userOsTokenShares = IVaultOsToken(inputData.vault).osTokenPositions(inputData.user);
        uint256 userOsTokenAssets = _osTokenController.convertToAssets(userOsTokenShares);

        // calculate max osToken assets that user can mint
        uint256 maxOsTokenAssets = Math.mulDiv(userStakeAssets, vaultLtvPercent, _maxPercent);

        // add slippage to maxOsTokenAssets
        uint256 slippage = _getOsTokenHourRewardAssets(maxOsTokenAssets);
        maxOsTokenAssets = maxOsTokenAssets > slippage ? maxOsTokenAssets - slippage : 0;

        // calculate osToken assets to mint based on user input
        uint256 mintOsTokenAssets = Math.mulDiv(inputData.stakeAssets, vaultLtvPercent, _maxPercent);

        if (maxOsTokenAssets <= userOsTokenAssets) {
            mintOsTokenAssets = 0;
        } else if (maxOsTokenAssets <= userOsTokenAssets + mintOsTokenAssets) {
            mintOsTokenAssets = maxOsTokenAssets - userOsTokenAssets;
        }

        // calculate osToken shares to mint
        if (mintOsTokenAssets > 0) {
            outputData.receivedOsTokenShares = _osTokenController.convertToShares(mintOsTokenAssets);
        }
    }

    function calculateUnstake(
        UnstakeInput memory inputData
    ) external returns (UnstakeOutput memory outputData) {
        // check whether state can be updated
        if (_keeper.canHarvest(inputData.vault)) {
            IVaultState(inputData.vault).updateState(inputData.harvestParams);
        }

        // fetch user osToken position
        uint256 leftOsTokenShares = IVaultOsToken(inputData.vault).osTokenPositions(inputData.user);

        // calculate osToken shares to burn
        outputData.burnOsTokenShares = Math.min(inputData.osTokenShares, leftOsTokenShares);

        // update osToken shares
        uint256 osTokenHourFeeShares = _getOsTokenHourFeeShares(leftOsTokenShares);
        leftOsTokenShares = leftOsTokenShares + osTokenHourFeeShares - outputData.burnOsTokenShares;

        // update osToken assets
        uint256 leftOsTokenAssets = _osTokenController.convertToAssets(leftOsTokenShares);
        leftOsTokenAssets += _getOsTokenHourRewardAssets(leftOsTokenAssets);

        // fetch user stake assets and shares
        uint256 stakeShares = IVaultState(inputData.vault).getShares(inputData.user);
        uint256 stakeAssets = IVaultState(inputData.vault).convertToAssets(stakeShares);

        // vault LTV
        uint256 vaultLtvPercent = _getVaultLtvPercent(inputData.vault);

        // calculate max unstake assets
        uint256 lockedAssets = Math.min(Math.mulDiv(leftOsTokenAssets, _maxPercent, vaultLtvPercent), stakeAssets);
        stakeAssets -= lockedAssets;

        // calculate received assets
        outputData.receivedAssets =
            Math.mulDiv(_osTokenController.convertToAssets(outputData.burnOsTokenShares), _maxPercent, vaultLtvPercent);
        if (stakeAssets < outputData.receivedAssets) {
            outputData.receivedAssets = stakeAssets;
        }
        stakeAssets -= outputData.receivedAssets;

        // if less than 1% of stake assets left, add them to received assets
        if (Math.mulDiv(outputData.receivedAssets, 0.01 ether, 1 ether) >= stakeAssets) {
            outputData.receivedAssets += stakeAssets;
        }
        outputData.exitQueueShares =
            Math.min(stakeShares, IVaultState(inputData.vault).convertToShares(outputData.receivedAssets));
    }

    function getBalance(
        BalanceInput memory inputData
    ) external returns (uint256 receivedAssets) {
        // check whether state can be updated
        if (_keeper.canHarvest(inputData.vault)) {
            IVaultState(inputData.vault).updateState(inputData.harvestParams);
        }

        // fetch user osToken position
        uint256 mintedOsTokenShares = IVaultOsToken(inputData.vault).osTokenPositions(inputData.user);
        uint256 balanceOsTokenShares = inputData.osTokenShares;

        // calculate osToken shares to burn
        uint256 burnOsTokenShares = Math.min(balanceOsTokenShares, mintedOsTokenShares);
        mintedOsTokenShares -= burnOsTokenShares;
        balanceOsTokenShares -= burnOsTokenShares;

        // update osToken assets
        uint256 leftOsTokenAssets = _osTokenController.convertToAssets(mintedOsTokenShares);

        // fetch user stake assets and shares
        uint256 stakeShares = IVaultState(inputData.vault).getShares(inputData.user);
        uint256 stakeAssets = IVaultState(inputData.vault).convertToAssets(stakeShares);

        // vault LTV
        uint256 vaultLtvPercent = _getVaultLtvPercent(inputData.vault);

        // calculate max unstake assets
        uint256 lockedAssets = Math.min(Math.mulDiv(leftOsTokenAssets, _maxPercent, vaultLtvPercent), stakeAssets);
        stakeAssets -= lockedAssets;

        // calculate received assets
        receivedAssets =
            Math.mulDiv(_osTokenController.convertToAssets(burnOsTokenShares), _maxPercent, vaultLtvPercent);
        if (stakeAssets < receivedAssets) {
            receivedAssets = stakeAssets;
        }
        stakeAssets -= receivedAssets;

        // if less than 1% of stake assets left, add them to received assets
        if (Math.mulDiv(receivedAssets, 0.01 ether, 1 ether) >= stakeAssets) {
            receivedAssets += stakeAssets;
        }
        receivedAssets += _osTokenController.convertToAssets(balanceOsTokenShares);
    }

    function _getVaultLtvPercent(
        address vault
    ) private view returns (uint256) {
        uint256 vaultVersion = IVaultVersion(vault).version();
        if (vaultVersion > 1) {
            return _osTokenConfigV2.getConfig(vault).ltvPercent;
        } else {
            // convert to 1e18 V1 LTV
            return _osTokenConfigV1.ltvPercent() * 1e14;
        }
    }

    function _getOsTokenHourRewardAssets(
        uint256 osTokenAssets
    ) private view returns (uint256) {
        uint256 avgRewardPerSecond = _osTokenController.avgRewardPerSecond();
        return Math.mulDiv(osTokenAssets, avgRewardPerSecond * 1 hours, 1e18);
    }

    function _getOsTokenHourFeeShares(
        uint256 osTokenShares
    ) private view returns (uint256) {
        uint256 osTokenAssets = _osTokenController.convertToAssets(osTokenShares);
        uint256 osTokenRewardAssets = _getOsTokenHourRewardAssets(osTokenAssets);
        uint256 osTokenFeeAssets = Math.mulDiv(osTokenRewardAssets, _osTokenController.feePercent(), 10_000);
        return _osTokenController.convertToShares(osTokenFeeAssets);
    }
}
