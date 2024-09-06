// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.26;

/**
 * @title IStrategy
 * @author StakeWise
 * @notice Defines the interface for the Strategy contract
 */
interface IStrategy {
    /**
     * @notice Strategy Unique Identifier
     * @return The unique identifier of the strategy
     */
    function strategyId() external pure returns (bytes32);
}
