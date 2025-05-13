// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.26;

import {Address} from '@openzeppelin/contracts/utils/Address.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IVaultGnoStaking} from '@stakewise-core/interfaces/IVaultGnoStaking.sol';
import {ISavingsXDaiAdapter} from './interfaces/ISavingsXDaiAdapter.sol';
import {BaseTokensConverter, IBaseTokensConverter} from './BaseTokensConverter.sol';

/**
 * @title GnoTokensConverter
 * @author StakeWise
 * @notice Defines functionality for converting tokens to GNO and returning them to the Vault
 */
contract GnoTokensConverter is BaseTokensConverter {
    ISavingsXDaiAdapter private immutable _savingsXDaiAdapter;

    /**
     * @dev Constructor
     * @param composableCoW The address of the ComposableCoW contract
     * @param swapOrderHandler The address of the SwapOrderHandler contract
     * @param assetToken The address of the GNO token
     * @param relayer The address of the Cowswap relayer contract
     * @param savingsXDaiAdapter The address of the SavingsXDaiAdapter contract
     */
    constructor(
        address composableCoW,
        address swapOrderHandler,
        address assetToken,
        address relayer,
        address savingsXDaiAdapter
    ) BaseTokensConverter(composableCoW, swapOrderHandler, assetToken, relayer) {
        _savingsXDaiAdapter = ISavingsXDaiAdapter(savingsXDaiAdapter);
    }

    /// @inheritdoc IBaseTokensConverter
    function initialize(
        address _vault
    ) external initializer {
        __BaseTokensConverter_init(_vault);
        IERC20(_assetToken).approve(_vault, type(uint256).max);
    }

    /// @inheritdoc IBaseTokensConverter
    function transferAssets() external override {
        uint256 balance = IERC20(_assetToken).balanceOf(address(this));
        if (balance > 0) {
            IVaultGnoStaking(vault).donateAssets(balance);
        }
    }

    /// @inheritdoc IBaseTokensConverter
    function createSwapOrders(
        address[] calldata tokens
    ) public override {
        // convert xDAI to sDAI
        uint256 balance = address(this).balance;
        if (balance > 0) {
            _savingsXDaiAdapter.depositXDAI{value: balance}(address(this));
        }
        super.createSwapOrders(tokens);
    }

    /**
     * @dev Function for receiving assets
     */
    receive() external payable {}

    /// @inheritdoc BaseTokensConverter
    function _supportedVaultVersion() internal pure override returns (uint8) {
        return 3;
    }
}
