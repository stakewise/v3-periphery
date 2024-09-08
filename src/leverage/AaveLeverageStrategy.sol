// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.26;

import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/math/SafeCast.sol';
import {IPoolDataProvider} from '@aave-core/interfaces/IPoolDataProvider.sol';
import {IPool} from '@aave-core/interfaces/IPool.sol';
import {IScaledBalanceToken} from '@aave-core/interfaces/IScaledBalanceToken.sol';
import {WadRayMath} from '@aave-core/protocol/libraries/math/WadRayMath.sol';
import {IStrategyProxy} from '../interfaces/IStrategyProxy.sol';
import {LeverageStrategy} from './LeverageStrategy.sol';

/**
 * @title AaveLeverageStrategy
 * @author StakeWise
 * @notice Defines the Aave leverage strategy functionality
 */
abstract contract AaveLeverageStrategy is LeverageStrategy {
    uint256 private constant _wad = 1e18;

    IPool private immutable _aavePool;
    IPoolDataProvider private immutable _aavePoolDataProvider;
    IScaledBalanceToken private immutable _aaveOsToken;
    IScaledBalanceToken private immutable _aaveVarDebtAssetToken;

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
        LeverageStrategy(
            osToken,
            assetToken,
            osTokenVaultController,
            osTokenConfig,
            osTokenFlashLoans,
            osTokenVaultEscrow,
            strategiesRegistry,
            strategyProxyImplementation,
            balancerVault
        )
    {
        _aavePool = IPool(aavePool);
        _aavePoolDataProvider = IPoolDataProvider(aavePoolDataProvider);
        _aaveOsToken = IScaledBalanceToken(aaveOsToken);
        _aaveVarDebtAssetToken = IScaledBalanceToken(aaveVarDebtAssetToken);
    }

    /// @inheritdoc LeverageStrategy
    function _getBorrowLtv() internal view override returns (uint256) {
        uint256 emodeCategory = _aavePoolDataProvider.getReserveEModeCategory(address(_osToken));
        // convert to 1e18 precision
        uint256 aaveLtv = uint256(_aavePool.getEModeCategoryData(SafeCast.toUint8(emodeCategory)).ltv) * 1e14;

        // check whether there is max borrow LTV percent set in the strategy config
        bytes memory maxBorrowLtvPercentConfig =
            _strategiesRegistry.getStrategyConfig(strategyId(), _maxBorrowLtvPercentConfigName);
        if (maxBorrowLtvPercentConfig.length == 0) {
            return aaveLtv;
        }
        return Math.min(aaveLtv, abi.decode(maxBorrowLtvPercentConfig, (uint256)));
    }

    /// @inheritdoc LeverageStrategy
    function _getBorrowState(address proxy)
        internal
        view
        override
        returns (uint256 borrowedAssets, uint256 suppliedOsTokenShares)
    {
        suppliedOsTokenShares = _aaveOsToken.scaledBalanceOf(proxy);
        if (suppliedOsTokenShares != 0) {
            uint256 normalizedIncome = _aavePool.getReserveNormalizedIncome(address(_osToken));
            suppliedOsTokenShares = WadRayMath.rayMul(suppliedOsTokenShares, normalizedIncome);
        }

        borrowedAssets = _aaveVarDebtAssetToken.scaledBalanceOf(proxy);
        if (borrowedAssets != 0) {
            uint256 normalizedDebt = _aavePool.getReserveNormalizedVariableDebt(address(_assetToken));
            borrowedAssets = WadRayMath.rayMul(borrowedAssets, normalizedDebt);
        }
    }

    /// @inheritdoc LeverageStrategy
    function _supplyOsTokenShares(address proxy, uint256 osTokenShares) internal override {
        IStrategyProxy(proxy).execute(
            address(_aavePool),
            abi.encodeWithSelector(_aavePool.supply.selector, address(_osToken), osTokenShares, proxy, 0)
        );
    }

    /// @inheritdoc LeverageStrategy
    function _withdrawOsTokenShares(address proxy, uint256 osTokenShares) internal override {
        IStrategyProxy(proxy).execute(
            address(_aavePool),
            abi.encodeWithSelector(_aavePool.withdraw.selector, address(_osToken), osTokenShares, proxy)
        );
    }

    /// @inheritdoc LeverageStrategy
    function _borrowAssets(address proxy, uint256 amount) internal override {
        IStrategyProxy(proxy).execute(
            address(_aavePool),
            abi.encodeWithSelector(_aavePool.borrow.selector, address(_assetToken), amount, 2, 0, proxy)
        );
    }

    /// @inheritdoc LeverageStrategy
    function _repayAssets(address proxy, uint256 amount) internal override {
        IStrategyProxy(proxy).execute(
            address(_aavePool), abi.encodeWithSelector(_aavePool.repay.selector, address(_assetToken), amount, 2, proxy)
        );
    }

    /// @inheritdoc LeverageStrategy
    function _getOrCreateStrategyProxy(
        address vault,
        address user
    ) internal virtual override returns (address proxy, bool isCreated) {
        (proxy, isCreated) = super._getOrCreateStrategyProxy(vault, user);
        if (!isCreated) {
            return (proxy, isCreated);
        }

        // setup emode category
        uint256 emodeCategory = _aavePoolDataProvider.getReserveEModeCategory(address(_osToken));
        IStrategyProxy(proxy).execute(
            address(_aavePool), abi.encodeWithSelector(_aavePool.setUserEMode.selector, SafeCast.toUint8(emodeCategory))
        );

        // approve Aave pool to spend OsToken and AssetToken
        IStrategyProxy(proxy).execute(
            address(_osToken), abi.encodeWithSelector(_osToken.approve.selector, address(_aavePool), type(uint256).max)
        );
        IStrategyProxy(proxy).execute(
            address(_assetToken),
            abi.encodeWithSelector(_assetToken.approve.selector, address(_aavePool), type(uint256).max)
        );
    }
}
