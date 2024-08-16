// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.26;

import {Address} from '@openzeppelin/contracts/utils/Address.sol';
import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';
import {SafeCast} from '@openzeppelin/contracts/utils/math/SafeCast.sol';
import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {IPoolDataProvider} from '@aave-core/interfaces/IPoolDataProvider.sol';
import {IPool} from '@aave-core/interfaces/IPool.sol';
import {IPriceOracle} from '@aave-core/interfaces/IPriceOracle.sol';
import {LeverageStrategy} from './LeverageStrategy.sol';
import {IAaveLeverageStrategy} from './interfaces/IAaveLeverageStrategy.sol';

/**
 * @title AaveLeverageStrategy
 * @author StakeWise
 * @notice Defines the Aave leverage strategy functionality
 */
abstract contract AaveLeverageStrategy is Initializable, LeverageStrategy, IAaveLeverageStrategy {
    uint256 private constant _wad = 1e18;

    IPool private immutable _aavePool;
    IPoolDataProvider private immutable _aavePoolDataProvider;
    IPriceOracle private immutable _aaveOracle;

    /**
     * @dev Constructor
     * @param osToken The address of the OsToken contract
     * @param assetToken The address of the asset token contract (e.g. WETH)
     * @param osTokenVaultController The address of the OsTokenVaultController contract
     * @param osTokenConfig The address of the OsTokenConfig contract
     * @param osTokenVaultEscrow The address of the OsTokenVaultEscrow contract
     * @param balancerVault The address of the BalancerVault contract
     * @param balancerFeesCollector The address of the BalancerFeesCollector contract
     * @param aavePool The address of the Aave pool contract
     * @param aavePoolDataProvider The address of the Aave pool data provider contract
     * @param aaveOracle The address of the Aave oracle contract
     */
    constructor(
        address osToken,
        address assetToken,
        address osTokenVaultController,
        address osTokenConfig,
        address osTokenVaultEscrow,
        address balancerVault,
        address balancerFeesCollector,
        address aavePool,
        address aavePoolDataProvider,
        address aaveOracle
    )
        LeverageStrategy(
            osToken,
            assetToken,
            osTokenVaultController,
            osTokenConfig,
            osTokenVaultEscrow,
            balancerVault,
            balancerFeesCollector
        )
    {
        _aavePool = IPool(aavePool);
        _aavePoolDataProvider = IPoolDataProvider(aavePoolDataProvider);
        _aaveOracle = IPriceOracle(aaveOracle);
    }

    /// @inheritdoc LeverageStrategy
    function _getBorrowLtv() internal view override returns (uint256) {
        uint256 emodeCategory = _aavePoolDataProvider.getReserveEModeCategory(address(_osToken));
        // convert to 1e18 precision
        return _aavePool.getEModeCategoryData(SafeCast.toUint8(emodeCategory)).ltv * 1e14;
    }

    /// @inheritdoc LeverageStrategy
    function _getBorrowState() internal view override returns (uint256 borrowedAssets, uint256 suppliedOsTokenShares) {
        (uint256 totalCollateralBase, uint256 totalDebtBase,,,,) = _aavePool.getUserAccountData(address(this));
        uint256 assetTokenPrice = _aaveOracle.getAssetPrice(address(_assetToken));
        uint256 osTokenPrice = _aaveOracle.getAssetPrice(address(_osToken));

        borrowedAssets = Math.mulDiv(totalDebtBase, _wad, assetTokenPrice);
        suppliedOsTokenShares = Math.mulDiv(totalCollateralBase, _wad, osTokenPrice);
    }

    /// @inheritdoc LeverageStrategy
    function _supplyOsTokenShares(uint256 osTokenShares) internal override {
        _aavePool.supply(address(_osToken), osTokenShares, address(this), 0);
    }

    /// @inheritdoc LeverageStrategy
    function _withdrawOsTokenShares(uint256 osTokenShares) internal override {
        _aavePool.withdraw(address(_osToken), osTokenShares, address(this));
    }

    /// @inheritdoc LeverageStrategy
    function _borrowAssets(uint256 amount) internal override {
        _aavePool.borrow(address(_assetToken), amount, 2, 0, address(this));
    }

    /// @inheritdoc LeverageStrategy
    function _repayAssets(uint256 amount) internal override {
        _aavePool.repay(address(_assetToken), amount, 2, address(this));
    }

    /// @inheritdoc LeverageStrategy
    function _getMaxBorrowAssets() internal view override returns (uint256 amount) {
        (,, uint256 availableBorrowsBase,,,) = _aavePool.getUserAccountData(address(this));
        return Math.mulDiv(availableBorrowsBase, _wad, _aaveOracle.getAssetPrice(address(_assetToken)));
    }

    /**
     * @dev Initializes the AaveLeverageStrategy contract
     * @param _vault The address of the vault
     * @param _owner The address of the owner
     */
    function __AaveLeverageStrategy_init(address _vault, address _owner) internal onlyInitializing {
        __LeverageStrategy_init(_vault, _owner);
        _osToken.approve(address(_aavePool), type(uint256).max);
        _assetToken.approve(address(_aavePool), type(uint256).max);
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}
