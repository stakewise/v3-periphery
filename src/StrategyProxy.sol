// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.26;

import {Initializable} from '@openzeppelin/contracts/proxy/utils/Initializable.sol';
import {ReentrancyGuardTransient} from '@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol';
import {OwnableUpgradeable} from '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import {Address} from '@openzeppelin/contracts/utils/Address.sol';
import {IStrategyProxy} from './interfaces/IStrategyProxy.sol';

/**
 * @title StrategyProxy
 * @author StakeWise
 * @notice Proxy contract for executing transactions on behalf of the Strategy.
 */
contract StrategyProxy is Initializable, ReentrancyGuardTransient, OwnableUpgradeable, IStrategyProxy {
    /**
     * @dev Constructor
     */
    constructor() {
        _disableInitializers();
    }

    /// @inheritdoc IStrategyProxy
    function initialize(
        address initialOwner
    ) external initializer {
        __Ownable_init(initialOwner);
    }

    /// @inheritdoc IStrategyProxy
    function execute(
        address target,
        bytes memory data
    ) external payable onlyOwner returns (bytes memory) {
        if (msg.value > 0) {
            return executeWithValue(target, data, msg.value);
        } else {
            return Address.functionCall(target, data);
        }
    }

    /// @inheritdoc IStrategyProxy
    function executeWithValue(
        address target,
        bytes memory data,
        uint256 value
    ) public override onlyOwner returns (bytes memory) {
        return Address.functionCallWithValue(target, data, value);
    }

    /// @inheritdoc IStrategyProxy
    function sendValue(
        address payable recipient,
        uint256 amount
    ) external onlyOwner nonReentrant {
        Address.sendValue(recipient, amount);
    }

    /**
     * @dev Function for receiving assets
     */
    receive() external payable {}
}
