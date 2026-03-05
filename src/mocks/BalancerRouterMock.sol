// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.26;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {Initializable} from '@openzeppelin/contracts/proxy/utils/Initializable.sol';
import {UUPSUpgradeable} from '@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol';
import {OwnableUpgradeable} from '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import {IOsTokenVaultController} from '@stakewise-core/interfaces/IOsTokenVaultController.sol';
import {IBalancerRouter} from '../leverage/interfaces/IBalancerRouter.sol';

/**
 * @title BalancerRouterMock
 * @author StakeWise
 * @notice Defines the mock for the Balancer V3 Router contract
 */
contract BalancerRouterMock is IBalancerRouter, Initializable, UUPSUpgradeable, OwnableUpgradeable {
    error SwapExpired();
    error InvalidSwap();
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

    function swapSingleTokenExactOut(
        address,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 exactAmountOut,
        uint256 maxAmountIn,
        uint256 deadline,
        bool,
        bytes calldata
    ) external payable override returns (uint256 amountIn) {
        if (deadline < block.timestamp) {
            revert SwapExpired();
        }

        if (address(tokenIn) != address(_osToken) || address(tokenOut) != address(_assetToken)) {
            revert InvalidSwap();
        }

        amountIn = _osTokenVaultController.convertToShares(exactAmountOut);
        if (amountIn > maxAmountIn) {
            revert LimitExceeded();
        }

        SafeERC20.safeTransferFrom(_osToken, msg.sender, address(this), amountIn);
        SafeERC20.safeTransfer(_assetToken, msg.sender, exactAmountOut);
    }

    function drain() external onlyOwner {
        SafeERC20.safeTransfer(_assetToken, msg.sender, _assetToken.balanceOf(address(this)));
        SafeERC20.safeTransfer(_osToken, msg.sender, _osToken.balanceOf(address(this)));
    }

    function _authorizeUpgrade(
        address
    ) internal override onlyOwner {}
}
