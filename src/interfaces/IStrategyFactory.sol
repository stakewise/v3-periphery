// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.26;

/**
 * @title IStrategyFactory
 * @author StakeWise
 * @notice Defines the interface for the StrategyFactory contract
 */
interface IStrategyFactory {
    /**
     * @notice The address of the Strategy implementation contract used for proxy creation
     * @return The address of the Strategy implementation contract
     */
    function implementation() external view returns (address);
}
