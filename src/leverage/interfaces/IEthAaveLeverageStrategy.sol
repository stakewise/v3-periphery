// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.26;

import {ILeverageStrategy} from './ILeverageStrategy.sol';

/**
 * @title IEthAaveLeverageStrategy
 * @author StakeWise
 * @notice Interface for EthAaveLeverageStrategy contract
 */
interface IEthAaveLeverageStrategy is ILeverageStrategy {
    /**
     * @notice Event emitted on assets received
     * @param sender The address that sent the assets
     * @param amount The amount of assets received
     */
    event AssetsReceived(address sender, uint256 amount);

    /**
     * @notice Initializes the strategy with the given vault and owner
     * @param _vault The address of the vault
     * @param _owner The address of the owner
     */
    function initialize(address _vault, address _owner) external;
}