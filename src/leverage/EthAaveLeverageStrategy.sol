// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.26;

import {WETH9} from '@aave-core/dependencies/weth/WETH9.sol';
import {IEthVault} from '@stakewise-core/interfaces/IEthVault.sol';
import {IStrategy} from '../interfaces/IStrategy.sol';
import {IStrategyProxy} from '../interfaces/IStrategyProxy.sol';
import {LeverageStrategy} from './LeverageStrategy.sol';
import {AaveLeverageStrategy} from './AaveLeverageStrategy.sol';

/**
 * @title EthAaveLeverageStrategy
 * @author StakeWise
 * @notice Defines the Aave leverage strategy functionality on Ethereum
 */
contract EthAaveLeverageStrategy is AaveLeverageStrategy {
    /**
     * @dev Constructor
     * @param osToken The address of the OsToken contract
     * @param assetToken The address of the asset token contract (e.g. WETH)
     * @param osTokenVaultController The address of the OsTokenVaultController contract
     * @param osTokenConfig The address of the OsTokenConfig contract
     * @param osTokenFlashLoans The address of the OsTokenFlashLoans contract
     * @param osTokenVaultEscrow The address of the OsTokenVaultEscrow contract
     * @param strategiesRegistry The address of the StrategiesRegistry contract
     * @param strategyProxyImplementation The address of the StrategyProxy implementation
     * @param balancerVault The address of the BalancerVault contract
     * @param aavePool The address of the Aave pool contract
     * @param aavePoolDataProvider The address of the Aave pool data provider contract
     * @param aaveOsToken The address of the Aave OsToken contract
     * @param aaveVarDebtAssetToken The address of the Aave variable debt asset token contract
     */
    constructor(
        address osToken,
        address assetToken,
        address osTokenVaultController,
        address osTokenConfig,
        address osTokenFlashLoans,
        address osTokenVaultEscrow,
        address strategiesRegistry,
        address strategyProxyImplementation,
        address balancerVault,
        address aavePool,
        address aavePoolDataProvider,
        address aaveOsToken,
        address aaveVarDebtAssetToken
    )
        AaveLeverageStrategy(
            osToken,
            assetToken,
            osTokenVaultController,
            osTokenConfig,
            osTokenFlashLoans,
            osTokenVaultEscrow,
            strategiesRegistry,
            strategyProxyImplementation,
            balancerVault,
            aavePool,
            aavePoolDataProvider,
            aaveOsToken,
            aaveVarDebtAssetToken
        )
    {}

    /// @inheritdoc IStrategy
    function strategyId() public pure override returns (bytes32) {
        return keccak256('EthAaveLeverageStrategy');
    }

    /// @inheritdoc LeverageStrategy
    function _claimOsTokenVaultEscrowAssets(
        address vault,
        address proxy,
        uint256 positionTicket,
        uint256 osTokenShares
    ) internal override returns (uint256 claimedAssets) {
        claimedAssets = super._claimOsTokenVaultEscrowAssets(vault, proxy, positionTicket, osTokenShares);
        if (claimedAssets == 0) return 0;

        // convert ETH to WETH
        IStrategyProxy(proxy).executeWithValue(
            address(_assetToken),
            abi.encodeWithSelector(WETH9(payable(address(_assetToken))).deposit.selector),
            claimedAssets
        );
    }

    /// @inheritdoc LeverageStrategy
    function _mintOsTokenShares(
        address vault,
        address proxy,
        uint256 depositAssets,
        uint256 mintOsTokenShares
    ) internal override returns (uint256) {
        IStrategyProxy(proxy).execute(
            address(_assetToken),
            abi.encodeWithSelector(WETH9(payable(address(_assetToken))).withdraw.selector, depositAssets)
        );
        uint256 balanceBefore = _osToken.balanceOf(proxy);
        IStrategyProxy(proxy).executeWithValue(
            vault,
            abi.encodeWithSelector(
                IEthVault(vault).depositAndMintOsToken.selector, proxy, mintOsTokenShares, address(0)
            ),
            depositAssets
        );
        return _osToken.balanceOf(proxy) - balanceBefore;
    }

    /// @inheritdoc LeverageStrategy
    function _transferAssets(address proxy, address receiver, uint256 amount) internal override {
        IStrategyProxy(proxy).execute(
            address(_assetToken), abi.encodeWithSelector(WETH9(payable(address(_assetToken))).withdraw.selector, amount)
        );
        IStrategyProxy(proxy).sendValue(payable(receiver), amount);
    }
}
