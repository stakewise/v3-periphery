// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.26;

import {IStrategyFactory} from '../../interfaces/IStrategyFactory.sol';

/**
 * @title ILeverageStrategyFactory
 * @author StakeWise
 * @notice Defines the interface for the LeverageStrategyFactory contract
 */
interface ILeverageStrategyFactory is IStrategyFactory {
    /**
     * @notice Event emitted on a leverage strategy creation
     * @param strategy The address of the created leverage strategy
     * @param owner The address of the leverage strategy owner
     * @param vault The address of the vault used for the leverage
     */
    event LeverageStrategyCreated(address indexed strategy, address indexed owner, address indexed vault);

    /**
     * @notice Create Strategy
     * @param vault The address of the vault used for the leverage
     * @return strategy The address of the created leverage strategy
     */
    function createStrategy(address vault) external returns (address strategy);
}
