// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.26;

import {Address} from '@openzeppelin/contracts/utils/Address.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {WETH9} from '@aave-core/dependencies/weth/WETH9.sol';
import {IVaultEthStaking} from '@stakewise-core/interfaces/IVaultEthStaking.sol';
import {BaseTokensConverter, IBaseTokensConverter} from './BaseTokensConverter.sol';

/**
 * @title EthTokensConverter
 * @author StakeWise
 * @notice Defines functionality for converting tokens to ETH and returning them to the Vault
 */
contract EthTokensConverter is BaseTokensConverter {
    /**
     * @dev Constructor
     * @param composableCoW The address of the ComposableCoW contract
     * @param swapOrderHandler The address of the SwapOrderHandler contract
     * @param assetToken The address of the WETH token
     * @param relayer The address of the Cowswap relayer contract
     */
    constructor(
        address composableCoW,
        address swapOrderHandler,
        address assetToken,
        address relayer
    ) BaseTokensConverter(composableCoW, swapOrderHandler, assetToken, relayer) {}

    /// @inheritdoc IBaseTokensConverter
    function transferAssets() external override {
        uint256 balance = IERC20(_assetToken).balanceOf(address(this));
        if (balance > 0) {
            WETH9(payable(_assetToken)).withdraw(balance);
        }
        uint256 value = address(this).balance;
        if (value > 0) {
            IVaultEthStaking(vault).donateAssets{value: value}();
        }
    }

    /**
     * @dev Function for receiving assets
     */
    receive() external payable {}

    /// @inheritdoc BaseTokensConverter
    function _supportedVaultVersion() internal pure override returns (uint8) {
        return 5;
    }
}
