// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.26;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {UUPSUpgradeable} from '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import {OwnableUpgradeable} from '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import {IOsTokenVaultController} from '@stakewise-core/interfaces/IOsTokenVaultController.sol';
import {IBalancerVault} from '../leverage/interfaces/IBalancerVault.sol';

/**
 * @title BalancerVaultMock
 * @author StakeWise
 * @notice Defines the mock for the Balancer Vault contract
 */
contract BalancerVaultMock is IBalancerVault, Initializable, UUPSUpgradeable, OwnableUpgradeable {
    error SwapExpired();
    error InvalidSingleSwap();
    error InvalidFundManagement();
    error LimitExceeded();

    IERC20 private immutable _osToken;
    IERC20 private immutable _assetToken;
    IOsTokenVaultController private immutable _osTokenVaultController;

    constructor(address osToken, address assetToken, address osTokenVaultController) {
        _osToken = IERC20(osToken);
        _assetToken = IERC20(assetToken);
        _osTokenVaultController = IOsTokenVaultController(osTokenVaultController);
    }

    function initialize(
        address initialOwner
    ) external initializer {
        __Ownable_init(initialOwner);
    }

    function swap(
        SingleSwap calldata singleSwap,
        FundManagement calldata funds,
        uint256 limit,
        uint256 deadline
    ) external payable override returns (uint256 amountIn) {
        if (deadline < block.timestamp) {
            revert SwapExpired();
        }

        if (
            singleSwap.kind != SwapKind.GIVEN_OUT || singleSwap.assetIn != address(_osToken)
                || singleSwap.assetOut != address(_assetToken)
        ) {
            revert InvalidSingleSwap();
        }

        if (funds.sender != msg.sender || funds.fromInternalBalance || funds.toInternalBalance) {
            revert InvalidFundManagement();
        }

        amountIn = _osTokenVaultController.convertToShares(singleSwap.amount);
        if (amountIn > limit) {
            revert LimitExceeded();
        }

        SafeERC20.safeTransferFrom(_osToken, msg.sender, address(this), amountIn);
        SafeERC20.safeTransfer(_assetToken, funds.recipient, singleSwap.amount);
    }

    function drain() external onlyOwner {
        SafeERC20.safeTransfer(_assetToken, msg.sender, _assetToken.balanceOf(address(this)));
        SafeERC20.safeTransfer(_osToken, msg.sender, _osToken.balanceOf(address(this)));
    }

    function _authorizeUpgrade(
        address
    ) internal override onlyOwner {}
}
