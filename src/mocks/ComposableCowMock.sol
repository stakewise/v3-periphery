// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.26;

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IConditionalOrder} from '@composable-cow/interfaces/IConditionalOrder.sol';
import {IComposableCoW} from '../converters/interfaces/IComposableCoW.sol';
import {SwapOrderHandler} from '../converters/SwapOrderHandler.sol';

/**
 * @title ComposableCowMock
 * @author StakeWise
 * @notice Mock for ComposableCow contract
 */
contract ComposableCowMock is Ownable, IComposableCoW {
    error InvalidToken();

    mapping(address token => uint256 rate) public rates;
    uint256 public sellTokenRate;

    IERC20 public assetToken;

    constructor(address owner_, address _assetToken) Ownable(owner_) {
        assetToken = IERC20(_assetToken);
    }

    function setTokenRate(address token, uint256 rate) external onlyOwner {
        rates[token] = rate;
    }

    function sweepTokens(
        address[] calldata tokens
    ) external onlyOwner {
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20(tokens[i]).transfer(msg.sender, IERC20(tokens[i]).balanceOf(address(this)));
        }
    }

    function convertToAssets(address token, uint256 amount) public view returns (uint256) {
        uint256 rate = rates[token];
        if (rate == 0) {
            revert InvalidToken();
        }
        return (amount * rate) / 1e18;
    }

    function domainSeparator() external pure returns (bytes32) {
        return bytes32(0);
    }

    function isValidSafeSignature(
        address payable,
        address,
        bytes32,
        bytes32,
        bytes32,
        bytes calldata,
        bytes calldata
    ) external pure returns (bytes4 magic) {
        return bytes4(0);
    }

    function create(IConditionalOrder.ConditionalOrderParams calldata params, bool) external {
        SwapOrderHandler.Data memory data = abi.decode(params.staticInput, (SwapOrderHandler.Data));
        uint256 balance = IERC20(data.sellToken).balanceOf(msg.sender);
        if (balance == 0) {
            revert InvalidToken();
        }

        IERC20(data.sellToken).transferFrom(msg.sender, address(this), balance);
        assetToken.transfer(msg.sender, convertToAssets(data.sellToken, balance));
    }
}
