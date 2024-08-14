// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {Address} from '@openzeppelin/contracts/utils/Address.sol';
import {WETH9} from '@aave-core/dependencies/weth/WETH9.sol';
import {IWETHGateway} from './interfaces/IWETHGateway.sol';

/**
 * @title WETHGateway
 * @author StakeWise
 * @dev WETH9 uses transfer in withdraw method which is not working with proxies due to the out of gas issue.
 * @notice A contract that allows depositing and withdrawing Ether to and from WETH
 */
contract WETHGateway is IWETHGateway {
    address payable private immutable _weth;

    /**
     * @notice Constructor
     * @param weth The address of the WETH contract
     */
    constructor(address weth) {
        _weth = payable(weth);
    }

    /// @inheritdoc IWETHGateway
    function deposit() external payable {
        WETH9(_weth).deposit{value: msg.value}();
        SafeERC20.safeTransfer(IERC20(_weth), msg.sender, msg.value);
    }

    /// @inheritdoc IWETHGateway
    function withdraw(uint256 amount) external {
        SafeERC20.safeTransferFrom(IERC20(_weth), msg.sender, address(this), amount);
        WETH9(_weth).withdraw(amount);
        Address.sendValue(payable(msg.sender), amount);
    }

    /**
     * @dev Fallback function to receive Ether.
     */
    receive() external payable {}
}
