// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

/**
 * @title IWETHGateway
 * @author StakeWise
 * @notice Interface for WETHGateway contract
 */
interface IWETHGateway {
    /**
     * @notice Deposit Ether to WETH
     */
    function deposit() external payable;

    /**
     * @notice Withdraw Ether from WETH
     * @param amount The amount of Ether to withdraw
     */
    function withdraw(uint256 amount) external;
}
