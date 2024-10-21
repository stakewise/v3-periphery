// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {IOsTokenVaultController} from '@stakewise-core/interfaces/IOsTokenVaultController.sol';

contract AaveMock is Ownable {
    error ErrorInsufficientCollateral();
    error InvalidAssets();

    struct CollateralConfig {
        uint16 ltv;
        uint16 liquidationThreshold;
        uint16 liquidationBonus;
    }

    struct DebtData {
        uint256 principalDebt;
        uint256 lastUpdateTimestamp;
    }

    uint256 private constant WAD_TO_RAY = 1e9;
    uint256 private constant _WAD = 1e18;
    uint256 private constant _RAY = 1e27;

    IERC20 private immutable _osToken;
    IERC20 private immutable _assetToken;
    IOsTokenVaultController private immutable _osTokenVaultController;

    mapping(address => uint256) public balances; // user => balance
    mapping(address => DebtData) public userVariableDebt; // user => debt data
    mapping(address => uint8) public userEmodeCategory; // user => categoryId

    uint256 public varInterestRatePerSecond;

    constructor(address osToken, address assetToken, address osTokenVaultController) Ownable(msg.sender) {
        _osToken = IERC20(osToken);
        _assetToken = IERC20(assetToken);
        _osTokenVaultController = IOsTokenVaultController(osTokenVaultController);
    }

    function getAssetsPrices(
        address[] memory assets
    ) public view returns (uint256[] memory) {
        if (assets.length != 2 && assets[0] != address(_osToken) && assets[1] != address(_assetToken)) {
            revert InvalidAssets();
        }
        uint256[] memory response = new uint256[](2);
        response[0] = _osTokenVaultController.convertToAssets(1 ether);
        response[1] = 1 ether;
        return response;
    }

    function getUserVariableDebt(
        address user
    ) external view returns (uint256) {
        DebtData memory debtData = userVariableDebt[user];
        if (debtData.principalDebt > 0) {
            uint256 timeElapsed = block.timestamp - debtData.lastUpdateTimestamp;
            uint256 interestAccrued = (debtData.principalDebt * varInterestRatePerSecond * timeElapsed) / _RAY;
            debtData.principalDebt += interestAccrued;
        }
        return debtData.principalDebt;
    }

    function getReserveData(
        address asset
    )
        external
        view
        returns (
            uint256 unbacked,
            uint256 accruedToTreasuryScaled,
            uint256 totalAToken,
            uint256 totalStableDebt,
            uint256 totalVariableDebt,
            uint256 liquidityRate,
            uint256 variableBorrowRate,
            uint256 stableBorrowRate,
            uint256 averageStableBorrowRate,
            uint256 liquidityIndex,
            uint256 variableBorrowIndex,
            uint40 lastUpdateTimestamp
        )
    {
        unbacked = 0;
        accruedToTreasuryScaled = 0;
        totalAToken = 0;
        totalStableDebt = 0;
        totalVariableDebt = 0;
        liquidityRate = 0;
        stableBorrowRate = 0;
        averageStableBorrowRate = 0;
        liquidityIndex = 0;
        variableBorrowIndex = 0;
        lastUpdateTimestamp = uint40(block.timestamp);
        if (asset == address(_assetToken)) {
            variableBorrowRate = varInterestRatePerSecond * 365 days * WAD_TO_RAY;
        } else {
            variableBorrowRate = 0;
        }
    }

    function getUserAccountData(
        address user
    )
        external
        view
        virtual
        returns (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        )
    {
        address[] memory assets = new address[](2);
        assets[0] = address(_osToken);
        assets[1] = address(_assetToken);
        uint256[] memory prices = getAssetsPrices(assets);
        totalCollateralBase = Math.mulDiv(balances[user], prices[0], _WAD);
        totalDebtBase = Math.mulDiv(userVariableDebt[user].principalDebt, prices[1], _WAD);
        availableBorrowsBase = 0;
        currentLiquidationThreshold = 0;
        ltv = 0;
        healthFactor = 0;
    }

    function getEModeCategoryCollateralConfig(
        uint8
    ) public pure returns (CollateralConfig memory) {
        return CollateralConfig({ltv: 9300, liquidationThreshold: 9500, liquidationBonus: 10_100});
    }

    function getReserveNormalizedIncome(
        address
    ) external pure returns (uint256) {
        return _RAY; // Return constant value for simplicity
    }

    function getReserveNormalizedVariableDebt(
        address
    ) external pure returns (uint256) {
        return _RAY; // Return constant value for simplicity
    }

    function setVariableInterestRate(
        uint256 newRate
    ) external onlyOwner {
        varInterestRatePerSecond = newRate;
    }

    function setUserEMode(
        uint8 categoryId
    ) external {
        userEmodeCategory[msg.sender] = categoryId;
    }

    function accrueInterest(
        address user
    ) internal {
        DebtData storage debtData = userVariableDebt[user];

        if (debtData.principalDebt > 0) {
            uint256 timeElapsed = block.timestamp - debtData.lastUpdateTimestamp;
            uint256 interestAccrued = (debtData.principalDebt * varInterestRatePerSecond * timeElapsed) / _RAY;
            debtData.principalDebt += interestAccrued;
        }

        debtData.lastUpdateTimestamp = block.timestamp;
    }

    function repay(address, uint256 amount, uint256, address) external returns (uint256) {
        // Accrue interest before repayment
        accrueInterest(msg.sender);

        DebtData storage debtData = userVariableDebt[msg.sender];
        debtData.principalDebt -= amount;

        // Transfer tokens from msg.sender to the contract
        SafeERC20.safeTransferFrom(_assetToken, msg.sender, address(this), amount);
        return amount;
    }

    function borrow(address, uint256 amount, uint256, uint16, address) external {
        // Accrue interest before borrowing
        accrueInterest(msg.sender);

        DebtData storage debtData = userVariableDebt[msg.sender];

        debtData.principalDebt += amount;
        debtData.lastUpdateTimestamp = block.timestamp;

        _checkCollateral(msg.sender);

        // Transfer tokens to msg.sender
        SafeERC20.safeTransfer(_assetToken, msg.sender, amount);
    }

    function withdraw(address, uint256 amount, address to) external returns (uint256) {
        balances[msg.sender] -= amount;

        _checkCollateral(msg.sender);

        // Transfer tokens to 'to'
        SafeERC20.safeTransfer(_osToken, to, amount);
        return amount;
    }

    function supply(address, uint256 amount, address, uint16) external {
        // Increase the user's balance
        balances[msg.sender] += amount;

        // Transfer tokens from msg.sender to the contract
        SafeERC20.safeTransferFrom(_osToken, msg.sender, address(this), amount);
    }

    function _checkCollateral(
        address user
    ) private {
        accrueInterest(user);
        DebtData storage debtData = userVariableDebt[user];
        uint256 userBalance = balances[user];
        uint256 osTokenAssets = _osTokenVaultController.convertToAssets(userBalance);
        uint256 ltv = getEModeCategoryCollateralConfig(1).ltv;
        if (Math.mulDiv(osTokenAssets, ltv, 10_000) < debtData.principalDebt) {
            revert ErrorInsufficientCollateral();
        }
    }
}
