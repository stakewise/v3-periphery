// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

/**
 * @title IBalancerRouter
 * @author Balancer
 * @notice Interface for the Balancer V3 Router contract
 */
interface IBalancerRouter {
    /**
     * @dev Executes a single-token swap where the exact output amount is specified.
     * @param pool Address of the liquidity pool
     * @param tokenIn Token to be swapped from
     * @param tokenOut Token to be swapped to
     * @param exactAmountOut Exact amount of output tokens to receive
     * @param maxAmountIn Maximum amount of input tokens to spend
     * @param deadline Deadline for the swap
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
     * @param userData Additional data required for the swap
     * @return amountIn Actual amount of input tokens used
     */
    function swapSingleTokenExactOut(
        address pool,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint256 exactAmountOut,
        uint256 maxAmountIn,
        uint256 deadline,
        bool wethIsEth,
        bytes calldata userData
    ) external payable returns (uint256 amountIn);
}
