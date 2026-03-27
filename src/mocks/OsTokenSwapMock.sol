// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.26;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {Initializable} from '@openzeppelin/contracts/proxy/utils/Initializable.sol';
import {UUPSUpgradeable} from '@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol';
import {OwnableUpgradeable} from '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import {IOsTokenVaultController} from '@stakewise-core/interfaces/IOsTokenVaultController.sol';
import {IOsTokenSwap} from '../leverage/interfaces/IOsTokenSwap.sol';

/**
 * @title OsTokenSwapMock
 * @author StakeWise
 * @notice Mock implementation of IOsTokenSwap for testing
 */
contract OsTokenSwapMock is IOsTokenSwap, Initializable, UUPSUpgradeable, OwnableUpgradeable {
    error LimitExceeded();

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IERC20 private immutable _osToken;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IERC20 private immutable _assetToken;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IOsTokenVaultController private immutable _osTokenVaultController;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(
        address osToken,
        address assetToken,
        address osTokenVaultController
    ) {
        _osToken = IERC20(osToken);
        _assetToken = IERC20(assetToken);
        _osTokenVaultController = IOsTokenVaultController(osTokenVaultController);
        _disableInitializers();
    }

    function initialize(
        address initialOwner
    ) external initializer {
        __Ownable_init(initialOwner);
    }

    /// @inheritdoc IOsTokenSwap
    function swap(
        uint256 maxOsTokenIn,
        uint256 exactAmountOut
    ) external override {
        uint256 osTokenUsed = _osTokenVaultController.convertToShares(exactAmountOut);
        if (osTokenUsed > maxOsTokenIn) {
            revert LimitExceeded();
        }

        // send asset token to caller
        SafeERC20.safeTransfer(_assetToken, msg.sender, exactAmountOut);

        // return unused osToken to caller (tokens were sent to this contract before calling swap)
        uint256 unusedOsToken = _osToken.balanceOf(address(this)) - osTokenUsed;
        if (unusedOsToken > 0) {
            SafeERC20.safeTransfer(_osToken, msg.sender, unusedOsToken);
        }
    }

    function drain() external onlyOwner {
        SafeERC20.safeTransfer(_assetToken, msg.sender, _assetToken.balanceOf(address(this)));
        SafeERC20.safeTransfer(_osToken, msg.sender, _osToken.balanceOf(address(this)));
    }

    function _authorizeUpgrade(
        address
    ) internal override onlyOwner {}
}
