// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.26;

import {
    IERC20,
    GPv2Order,
    IConditionalOrder,
    IConditionalOrderGenerator,
    BaseConditionalOrder
} from '@composable-cow/BaseConditionalOrder.sol';
import {ConditionalOrdersUtilsLib as Utils} from '@composable-cow/types/ConditionalOrdersUtilsLib.sol';

/**
 * @title SwapOrderHandler
 * @author StakeWise
 * @notice Defines functionality for trading whenever its balance of a certain token is.
 */
contract SwapOrderHandler is BaseConditionalOrder {
    error InvalidBalance();

    struct Data {
        address sellToken;
        address buyToken;
        address receiver;
        uint32 validityPeriod;
        bytes32 appData;
    }

    /// @inheritdoc IConditionalOrderGenerator
    function getTradeableOrder(
        address owner,
        address,
        bytes32,
        bytes calldata staticInput,
        bytes calldata
    ) public view override returns (GPv2Order.Data memory order) {
        /// @dev Decode the payload into the trade parameters.
        SwapOrderHandler.Data memory data = abi.decode(staticInput, (Data));

        uint256 balance = IERC20(data.sellToken).balanceOf(owner);
        if (balance == 0) {
            revert InvalidBalance();
        }

        // ensures that orders queried shortly after one another result in the same hash (to avoid spamming the orderbook)
        order = GPv2Order.Data(
            IERC20(data.sellToken),
            IERC20(data.buyToken),
            data.receiver,
            balance,
            1, // 0 buy amount is not allowed
            Utils.validToBucket(data.validityPeriod),
            data.appData,
            0,
            GPv2Order.KIND_SELL,
            false,
            GPv2Order.BALANCE_ERC20,
            GPv2Order.BALANCE_ERC20
        );
    }
}
