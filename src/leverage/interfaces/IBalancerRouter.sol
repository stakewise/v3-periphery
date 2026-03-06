// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.26;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

/**
 * @title IBalancerRouter
 * @author Balancer
 * @notice Interface for the Balancer V3 BatchRouter contract
 */
interface IBalancerRouter {
    struct SwapPathStep {
        address pool;
        IERC20 tokenOut;
        bool isBuffer;
    }

    struct SwapPathExactAmountOut {
        IERC20 tokenIn;
        SwapPathStep[] steps;
        uint256 maxAmountIn;
        uint256 exactAmountOut;
    }

    /**
     * @dev Executes a swap with exact output amount, supporting multi-step paths with ERC4626 buffer wrapping.
     * @param paths Array of swap paths to execute
     * @param deadline Deadline for the swap
     * @param wethIsEth If true, incoming ETH will be wrapped to WETH and outgoing WETH will be unwrapped to ETH
     * @param userData Additional data required for the swap
     * @return pathAmountsIn Actual amounts of input tokens used per path
     * @return tokensIn Input tokens used
     * @return amountsIn Actual amounts of input tokens used
     */
    function swapExactOut(
        SwapPathExactAmountOut[] memory paths,
        uint256 deadline,
        bool wethIsEth,
        bytes calldata userData
    ) external payable returns (uint256[] memory pathAmountsIn, address[] memory tokensIn, uint256[] memory amountsIn);
}
