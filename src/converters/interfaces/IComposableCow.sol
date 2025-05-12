// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.26;

import {IConditionalOrder} from '@composable-cow/interfaces/IConditionalOrder.sol';

/**
 * @title IComposableCoW
 * @author mfw78 <mfw78@rndlabs.xyz>
 * @notice Interface for the Composable CoW Protocol
 */
interface IComposableCoW {
    /**
     * @dev A struct to encapsulate order parameters / offchain input
     */
    struct PayloadStruct {
        bytes32[] proof;
        IConditionalOrder.ConditionalOrderParams params;
        bytes offchainInput;
    }

    /**
     * @dev This function returns the domain separator used for signing orders.
     * @return The domain separator as a bytes32 value.
     */
    function domainSeparator() external view returns (bytes32);

    /**
     * @notice Authorise a single conditional order
     * @param params The parameters of the conditional order
     * @param dispatch Whether to dispatch the `ConditionalOrderCreated` event
     */
    function create(IConditionalOrder.ConditionalOrderParams calldata params, bool dispatch) external;

    /*
     * @dev This function does not make use of the `typeHash` parameter as CoW Protocol does not
     *      have more than one type.
     * @param encodeData Is the abi encoded `GPv2Order.Data`
     * @param payload Is the abi encoded `PayloadStruct`
     */
    function isValidSafeSignature(
        address payable safe,
        address sender,
        bytes32 _hash,
        bytes32 _domainSeparator,
        bytes32, // typeHash
        bytes calldata encodeData,
        bytes calldata payload
    ) external view returns (bytes4 magic);
}
