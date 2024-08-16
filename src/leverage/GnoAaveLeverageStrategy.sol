// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.26;

import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {Initializable} from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import {IGnoVault} from '@stakewise-core/interfaces/IGnoVault.sol';
import {IGnoAaveLeverageStrategy, ILeverageStrategy} from './interfaces/IGnoAaveLeverageStrategy.sol';
import {AaveLeverageStrategy, LeverageStrategy} from './AaveLeverageStrategy.sol';

/**
 * @title GnoAaveLeverageStrategy
 * @author StakeWise
 * @notice Defines the Aave leverage strategy functionality on Gnosis
 */
contract GnoAaveLeverageStrategy is Initializable, AaveLeverageStrategy, IGnoAaveLeverageStrategy {
    uint256 private constant _wad = 1e18;
    uint8 private constant _version = 1;

    /**
     * @dev Constructor
     * @param osToken The address of the OsToken contract
     * @param assetToken The address of the asset token contract (e.g. GNO)
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
        AaveLeverageStrategy(
            osToken,
            assetToken,
            osTokenVaultController,
            osTokenConfig,
            osTokenVaultEscrow,
            balancerVault,
            balancerFeesCollector,
            aavePool,
            aavePoolDataProvider,
            aaveOracle
        )
    {}

    /// @inheritdoc ILeverageStrategy
    function initialize(bytes calldata params) external initializer {
        (address _vault, address _owner) = abi.decode(params, (address, address));
        __GnoAaveLeverageStrategy_init(_vault, _owner);
    }

    /// @inheritdoc ILeverageStrategy
    function strategyId() public pure override(ILeverageStrategy, LeverageStrategy) returns (bytes32) {
        return keccak256('GnoAaveLeverageStrategy');
    }

    /// @inheritdoc ILeverageStrategy
    function version() public pure override(ILeverageStrategy, LeverageStrategy) returns (uint8) {
        return _version;
    }

    /// @inheritdoc LeverageStrategy
    function _mintOsTokenShares(address _vault, uint256 assets) internal override returns (uint256) {
        (uint256 stakedAssets, uint256 osTokenShares) = _getVaultState(_vault);
        uint256 vaultLtv = _getVaultLtv(_vault);
        uint256 maxOsTokenAssets = Math.mulDiv(stakedAssets + assets, vaultLtv, _wad);
        uint256 osTokenAssets = _osTokenVaultController.convertToAssets(osTokenShares);
        uint256 osTokenSharesToMint = _osTokenVaultController.convertToShares(maxOsTokenAssets - osTokenAssets);
        IGnoVault(_vault).deposit(assets, address(this), address(0));
        IGnoVault(_vault).mintOsToken(address(this), osTokenSharesToMint, address(0));
        return osTokenSharesToMint;
    }

    /// @inheritdoc LeverageStrategy
    function _transferAssets(address receiver, uint256 amount) internal override {
        SafeERC20.safeTransfer(_assetToken, receiver, amount);
    }

    /**
     * @dev Initializes the GnoAaveLeverageStrategy contract
     * @param _vault The address of the vault
     * @param _owner The address of the owner
     */
    function __GnoAaveLeverageStrategy_init(address _vault, address _owner) internal onlyInitializing {
        __AaveLeverageStrategy_init(_vault, _owner);
        _assetToken.approve(vault, type(uint256).max);
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}
