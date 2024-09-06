// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.26;

/**
 * @title IStrategyProxy
 * @author StakeWise
 * @notice Defines the interface for the StrategyProxy contract
 */
interface IStrategyProxy {
    /**
     * @notice Initializes the proxy.
     * @param initialOwner The address of the owner
     */
    function initialize(address initialOwner) external;

    /**
     * @notice Executes a call on the target contract. Can only be called by the owner.
     * @param target The address of the target contract
     * @param data The call data
     * @return The call result
     */
    function execute(address target, bytes memory data) external payable returns (bytes memory);

    /**
     * @notice Executes a call on the target contract with a native assets transfer. Can only be called by the owner.
     * @param target The address of the target contract
     * @param data The call data
     * @param value The amount of native assets to send
     * @return The call result
     */
    function executeWithValue(address target, bytes memory data, uint256 value) external returns (bytes memory);

    /**
     * @notice Function for sending native assets to the recipient. Can only be called by the owner.
     * @param recipient The address of the recipient
     * @param amount The amount of native assets to send
     */
    function sendValue(address payable recipient, uint256 amount) external;
}
