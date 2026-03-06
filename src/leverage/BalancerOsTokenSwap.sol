// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.26;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/math/SafeCast.sol';
import {ReentrancyGuardTransient} from '@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol';
import {IOsTokenSwap} from './interfaces/IOsTokenSwap.sol';
import {IBalancerRouter} from './interfaces/IBalancerRouter.sol';
import {IPermit2} from './interfaces/IPermit2.sol';

/**
 * @title BalancerOsTokenSwap
 * @author StakeWise
 * @notice Swaps osToken to asset token via Balancer V3 BatchRouter
 */
contract BalancerOsTokenSwap is ReentrancyGuardTransient, IOsTokenSwap {
    IERC20 private immutable _osToken;
    IERC20 private immutable _assetToken;
    IERC20 private immutable _wrappedAssetToken;
    IBalancerRouter private immutable _balancerRouter;
    address private immutable _balancerPool;
    IPermit2 private immutable _permit2;

    /**
     * @dev Constructor
     * @param osToken The address of the OsToken contract
     * @param assetToken The address of the asset token contract (e.g. WETH)
     * @param wrappedAssetToken The address of the wrapped asset token (e.g. waWETH)
     * @param balancerRouter The address of the Balancer V3 BatchRouter contract
     * @param balancerPool The address of the Balancer pool
     * @param permit2 The address of the Permit2 contract
     */
    constructor(
        address osToken,
        address assetToken,
        address wrappedAssetToken,
        address balancerRouter,
        address balancerPool,
        address permit2
    ) {
        _osToken = IERC20(osToken);
        _assetToken = IERC20(assetToken);
        _wrappedAssetToken = IERC20(wrappedAssetToken);
        _balancerRouter = IBalancerRouter(balancerRouter);
        _balancerPool = balancerPool;
        _permit2 = IPermit2(permit2);

        // approve osToken to Permit2 with max allowance
        _osToken.approve(permit2, type(uint256).max);
    }

    /// @inheritdoc IOsTokenSwap
    function swap(
        uint256 maxOsTokenIn,
        uint256 exactAmountOut
    ) external override nonReentrant {
        // set Permit2 allowance for BatchRouter
        _permit2.approve(
            address(_osToken),
            address(_balancerRouter),
            SafeCast.toUint160(maxOsTokenIn),
            SafeCast.toUint48(block.timestamp)
        );

        // build 2-step swap path: osToken -> wrappedAssetToken (pool) -> assetToken (buffer unwrap)
        IBalancerRouter.SwapPathStep[] memory steps = new IBalancerRouter.SwapPathStep[](2);
        steps[0] = IBalancerRouter.SwapPathStep({pool: _balancerPool, tokenOut: _wrappedAssetToken, isBuffer: false});
        steps[1] =
            IBalancerRouter.SwapPathStep({pool: address(_wrappedAssetToken), tokenOut: _assetToken, isBuffer: true});

        IBalancerRouter.SwapPathExactAmountOut[] memory paths = new IBalancerRouter.SwapPathExactAmountOut[](1);
        paths[0] = IBalancerRouter.SwapPathExactAmountOut({
            tokenIn: _osToken, steps: steps, maxAmountIn: maxOsTokenIn, exactAmountOut: exactAmountOut
        });

        // swap osToken to asset token via Balancer V3 BatchRouter
        _balancerRouter.swapExactOut(paths, block.timestamp, false, '');

        // return unused osToken to caller
        uint256 unusedOsToken = _osToken.balanceOf(address(this));
        if (unusedOsToken > 0) {
            SafeERC20.safeTransfer(_osToken, msg.sender, unusedOsToken);
        }

        // send asset token to caller
        SafeERC20.safeTransfer(_assetToken, msg.sender, exactAmountOut);
    }
}
