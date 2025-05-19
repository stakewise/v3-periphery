// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.26;

/**
 * @title ITokensConverterFactory
 * @author StakeWise
 * @notice Defines the interface for the TokensConverterFactory contract
 */
interface ITokensConverterFactory {
    /**
     * @dev Emitted when the tokens converter is created
     * @param sender The address of the sender
     * @param vault The address of the vault that converter is attached to
     * @param converter The address of the converter contract
     */
    event TokensConverterCreated(address sender, address indexed vault, address indexed converter);

    /**
     * @notice Get the address of the tokens converter implementation
     * @return The address of the tokens converter implementation
     */
    function implementation() external view returns (address);

    /**
     * @notice Get the address of the tokens converter for a given vault
     * @param vault The address of the vault
     * @return converter The address of the tokens converter
     */
    function getTokensConverter(
        address vault
    ) external view returns (address converter);

    /**
     * @notice Create a new tokens converter for a given vault
     * @param vault The address of the vault
     * @return converter The address of the tokens converter
     */
    function createConverter(
        address vault
    ) external returns (address converter);
}
