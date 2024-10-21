// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.26;

import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {UUPSUpgradeable} from '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import {OwnableUpgradeable} from '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import {AaveMock} from './AaveMock.sol';

/**
 * @title AaveVarDebtAssetTokenMock
 * @author StakeWise
 * @notice Defines the mock for the Aave asset variable debt token functionality
 */
contract AaveVarDebtAssetTokenMock is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    address private immutable _aaveMock;

    constructor(
        address aaveMock
    ) {
        _aaveMock = aaveMock;
    }

    function initialize(
        address initialOwner
    ) external initializer {
        __Ownable_init(initialOwner);
    }

    function scaledBalanceOf(
        address user
    ) external view returns (uint256) {
        return AaveMock(_aaveMock).getUserVariableDebt(user);
    }

    function _authorizeUpgrade(
        address
    ) internal override onlyOwner {}
}
