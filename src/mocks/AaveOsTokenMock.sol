// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {AaveMock} from './AaveMock.sol';

contract AaveOsTokenMock {
    address private immutable _aaveMock;

    constructor(
        address aaveMock
    ) {
        _aaveMock = aaveMock;
    }

    function scaledBalanceOf(
        address user
    ) external view returns (uint256) {
        return AaveMock(_aaveMock).balances(user);
    }
}
