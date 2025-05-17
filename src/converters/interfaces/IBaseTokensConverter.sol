// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.26;

/**
 * @title IBaseTokensConverter
 * @author StakeWise
 * @notice Defines the interface for the BaseTokensConverter contract
 */
interface IBaseTokensConverter {
    error InvalidHash();
    error InvalidToken();

    /**
     * @notice Emitted when the tokens conversion is submitted
     * @param tokens The list of tokens to be converted
     */
    event TokensConversionSubmitted(address[] tokens);

    /**
     * @notice Initialize the contract
     * @param _vault The address of the vault that converter is attached to
     */
    function initialize(
        address _vault
    ) external;

    /**
     * @notice Get the address of the vault that converter is attached to.
     * @return The address of the vault
     */
    function vault() external view returns (address);

    /**
     * @notice Create a CowSwap orders
     * @param tokens The list of tokens to be converted
     */
    function createSwapOrders(
        address[] memory tokens
    ) external;

    /**
     * @notice Re-arrange the request into something that ComposableCoW can understand
     * @param _hash GPv2Order.Data digest
     * @param signature The abi.encoded tuple of (GPv2Order.Data, ComposableCoW.PayloadStruct)
     */
    function isValidSignature(bytes32 _hash, bytes memory signature) external view returns (bytes4);

    /**
     * @notice Transfer accumulated assets to the Vault
     */
    function transferAssets() external;
}
