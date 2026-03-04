// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.26;

import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
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
        uint256 assets;
        IKeeperRewards.HarvestParams harvestParams;
    }

    struct UnstakeOutput {
        uint256 burnOsTokenShares;
        uint256 exitQueueShares;
        uint256 receivedAssets;
    }

    uint256 private constant _period = 10 minutes;
    uint256 private constant _maxPercent = 1e18;

    IERC20 private immutable _osToken;
    IKeeperRewards private immutable _keeper;
    IOsTokenConfigV1 private immutable _osTokenConfigV1;
    IOsTokenConfigV2 private immutable _osTokenConfigV2;
    IOsTokenVaultController private immutable _osTokenController;

    constructor(
        address osToken,
        address keeper,
        address osTokenConfigV1,
        address osTokenConfigV2,
        address osTokenController
    ) {
        _osToken = IERC20(osToken);
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
        userOsTokenShares += _getOsTokenPeriodFeeShares(userOsTokenShares);
        uint256 userOsTokenAssets = _osTokenController.convertToAssets(userOsTokenShares);
        userOsTokenAssets += _getOsTokenPeriodRewardAssets(userOsTokenAssets);

        // calculate max osToken assets that user can mint
        uint256 maxOsTokenAssets = Math.mulDiv(userStakeAssets, vaultLtvPercent, _maxPercent);

        // add slippage to maxOsTokenAssets
        uint256 slippage = _getOsTokenPeriodRewardAssets(maxOsTokenAssets);
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

    function getMaxUnstakeAssets(
        address vault,
        address user
    ) public view returns (uint256 unstakeAssets, uint256 balanceOsTokenShares) {
        // fetch user stake assets
        uint256 stakeShares = IVaultState(vault).getShares(user);
        uint256 stakeAssets = IVaultState(vault).convertToAssets(stakeShares);

        // fetch user minted osToken assets
        uint256 mintedOsTokenShares = IVaultOsToken(vault).osTokenPositions(user);

        // fetch user osToken balance
        balanceOsTokenShares = _osToken.balanceOf(user);

        // user burns osToken balance and reduce minted osToken shares accordingly
        uint256 burnOsTokenShares = Math.min(balanceOsTokenShares, mintedOsTokenShares);

        uint256 leftOsTokenShares = mintedOsTokenShares - burnOsTokenShares;
        leftOsTokenShares += _getOsTokenPeriodFeeShares(mintedOsTokenShares);

        uint256 leftOsTokenAssets = _osTokenController.convertToAssets(leftOsTokenShares);
        leftOsTokenAssets += _getOsTokenPeriodRewardAssets(leftOsTokenAssets);

        uint256 vaultLtvPercent = _getVaultLtvPercent(vault);
        uint256 lockedAssets = Math.min(Math.mulDiv(leftOsTokenAssets, _maxPercent, vaultLtvPercent), stakeAssets);
        unstakeAssets = stakeAssets - lockedAssets;
    }

    function calculateUnstake(
        UnstakeInput memory inputData
    ) external returns (UnstakeOutput memory outputData) {
        // check whether state can be updated
        if (_keeper.canHarvest(inputData.vault)) {
            IVaultState(inputData.vault).updateState(inputData.harvestParams);
        }

        // fetch max unstake assets
        (uint256 maxUnstakeAssets,) = getMaxUnstakeAssets(inputData.vault, inputData.user);

        // calculate unstake assets and shares based on user input
        outputData.receivedAssets = Math.min(inputData.assets, maxUnstakeAssets);
        outputData.exitQueueShares = IVaultState(inputData.vault).convertToShares(outputData.receivedAssets);

        // calculate max osToken shares to mint based on left stake assets
        uint256 vaultLtvPercent = _getVaultLtvPercent(inputData.vault);
        uint256 stakeAssets =
            IVaultState(inputData.vault).convertToAssets(IVaultState(inputData.vault).getShares(inputData.user));
        stakeAssets -= outputData.receivedAssets;
        uint256 maxMintOsTokenAssets = Math.mulDiv(stakeAssets, vaultLtvPercent, _maxPercent);
        // add slippage to maxMintOsTokenAssets
        uint256 slippage = _getOsTokenPeriodRewardAssets(maxMintOsTokenAssets);
        maxMintOsTokenAssets = maxMintOsTokenAssets > slippage ? maxMintOsTokenAssets - slippage : 0;
        uint256 maxMintOsTokenShares = _osTokenController.convertToShares(maxMintOsTokenAssets);

        // calculate osToken shares to burn
        uint256 mintedOsTokenShares = IVaultOsToken(inputData.vault).osTokenPositions(inputData.user);
        if (mintedOsTokenShares > maxMintOsTokenShares) {
            outputData.burnOsTokenShares = mintedOsTokenShares - maxMintOsTokenShares;
        }
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

    function _getOsTokenPeriodRewardAssets(
        uint256 osTokenAssets
    ) private view returns (uint256) {
        uint256 avgRewardPerSecond = _osTokenController.avgRewardPerSecond();
        return Math.mulDiv(osTokenAssets, avgRewardPerSecond * _period, 1e18);
    }

    function _getOsTokenPeriodFeeShares(
        uint256 osTokenShares
    ) private view returns (uint256) {
        uint256 osTokenAssets = _osTokenController.convertToAssets(osTokenShares);
        uint256 osTokenRewardAssets = _getOsTokenPeriodRewardAssets(osTokenAssets);
        uint256 osTokenFeeAssets = Math.mulDiv(osTokenRewardAssets, _osTokenController.feePercent(), 10_000);
        return _osTokenController.convertToShares(osTokenFeeAssets);
    }
}
