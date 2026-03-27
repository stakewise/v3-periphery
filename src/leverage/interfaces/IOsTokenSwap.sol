// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.26;

/**
 * @title IOsTokenSwap
 * @author StakeWise
 * @notice Interface for swapping osToken to asset token
 */
interface IOsTokenSwap {
    /**
     * @notice Swaps osToken for exact amount of asset token. Caller must transfer osToken to the contract first.
     *         Returns unused osToken to msg.sender and sends assetToken to msg.sender.
     * @param maxOsTokenIn The maximum amount of osToken to use for the swap
     * @param exactAmountOut The exact amount of asset token to receive
     */
    function swap(
        uint256 maxOsTokenIn,
        uint256 exactAmountOut
    ) external;
}
