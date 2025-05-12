// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.26;

/**
 * @title ISavingsXDaiAdapter
 * @author StakeWise
 * @notice Defines the interface for the SavingsXDaiAdapter
 */
interface ISavingsXDaiAdapter {
    /**
     * @notice Convert xDAI to sDAI
     * @param receiver The address of the receiver
     * @return The amount of sDAI received
     */
    function depositXDAI(
        address receiver
    ) external payable returns (uint256);
}
