// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ITribeOneAddressesProvider} from "../interfaces/ITribeOneAddressesProvider.sol";
import {ITribeOneAssetGateWay} from "../interfaces/ITribeOneAssetGateWay.sol";
import {IAToken} from "./interfaces/IAToken.sol";
import {IStableDebtToken} from "./interfaces/IStableDebtToken.sol";
import {IFundingPool} from "./interfaces/IFundingPool.sol";
import {ITribeOneFundingHakaChef} from "./interfaces/ITribeOneFundingHakaChef.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";
import {IWETH} from "../interfaces/IWETH.sol";
import {WadRayMath} from "./libraries/math/WadRayMath.sol";
import {PercentageMath} from "./libraries/math/PercentageMath.sol";
import {ReserveLogic} from "./libraries/logic/ReserveLogic.sol";
import {GenericLogic} from "./libraries/logic/GenericLogic.sol";
import {ValidationLogic} from "./libraries/logic/ValidationLogic.sol";
import {ReserveConfiguration} from "./libraries/configuration/ReserveConfiguration.sol";
import {UserConfiguration} from "./libraries/configuration/UserConfiguration.sol";
import {DataTypes} from "./libraries/types/DataTypes.sol";
import {TribeOneHelper} from "../libraries/TribeOneHelper.sol";
import {FundingPoolStorage} from "./FundingPoolStorage.sol";

import "hardhat/console.sol";

/**
 * @title FundingPool contract
 * @dev Main point of interaction with an TribeOne FundingPool
 * - Users can:
 *   # Deposit
 *   # Withdraw
 *   # Borrow
 *   # Repay
 **/
contract FundingPool is IFundingPool, FundingPoolStorage, Ownable {
    using SafeMath for uint256;
    using WadRayMath for uint256;
    using PercentageMath for uint256;

    using ReserveLogic for DataTypes.ReserveData;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using UserConfiguration for DataTypes.UserConfigurationMap;

    address public immutable WETH;
    uint256 private constant INTEREST_BURN_PERCENTAGE = 2000; // 20% burn
    uint256 private _borrowHealthFactor = 15000; // 150%

    constructor(address _WETH) {
        WETH = _WETH;
    }

    receive() external payable {
        assert(msg.sender == WETH); // only accept ETH via fallback from the WETH contract
    }

    modifier whenNotPaused() {
        require(!_paused, "FP: Paused");
        _;
    }

    modifier onlyTribeOne() {
        require(msg.sender == _addressesProvider.getTribeOne(), "Only TribeOne");
        _;
    }

    function borrowHealthFactor() external view override returns (uint256) {
        return _borrowHealthFactor;
    }

    function getInterestBurnPercentage() external pure override returns (uint256) {
        return INTEREST_BURN_PERCENTAGE;
    }

    /**
     * @param provider The address of the FundingPoolAddressesProvider
     **/
    function initialize(ITribeOneAddressesProvider provider, uint256 _percent) external onlyOwner {
        _addressesProvider = provider;
        _maxStableRateBorrowSizePercent = _percent; // 2500 means 25%

        emit IntializedFundingPool(address(provider), _percent);
    }

    /**
     * @dev Deposits an `amount` of underlying asset into the reserve, receiving in return overlying aTokens.
     * - E.g. User deposits 100 USDC and gets in return 100 aUSDC
     * @param asset The address of the underlying asset to deposit
     * @param amount The amount to be deposited
     * @param onBehalfOf The address that will receive the aTokens, same as msg.sender if the user
     *   wants to receive them on his own wallet, or a different address if the beneficiary of aTokens
     *   is a different wallet
     **/
    function deposit(
        address asset,
        uint256 amount,
        address onBehalfOf
    ) external override whenNotPaused {
        _deposit(asset, amount, onBehalfOf, false);
    }

    function depositETH(uint256 amount, address onBehalfOf) external payable override {
        require(_reserves[WETH].aTokenAddress != address(0), "FP: WETH reserve is still invalid");
        require(msg.value == amount, "Insufficient ETH fund");

        IWETH(WETH).deposit{value: amount}();

        _deposit(WETH, amount, onBehalfOf, true);
    }

    function _deposit(
        address asset,
        uint256 amount,
        address onBehalfOf,
        bool isETH
    ) private {
        DataTypes.ReserveData storage reserve = _reserves[asset];

        address aToken = reserve.aTokenAddress;
        require(aToken != address(0), "FundingPool: Invalid reserve asset");
        require(amount != 0, "FundingPool: Invalid amount");

        if (isETH) {
            assert(IWETH(WETH).transfer(aToken, amount));
        } else {
            TribeOneHelper.safeTransferFrom(asset, msg.sender, aToken, amount);
        }

        uint256 amountScaled = IAToken(aToken).mint(onBehalfOf, amount, reserve.liquidityIndex);
        ITribeOneFundingHakaChef(_addressesProvider.getHakaChef()).deposit(amountScaled, asset, onBehalfOf);

        emit Deposit(asset, msg.sender, onBehalfOf, amount, amountScaled);
    }

    /**
     * @dev Withdraws an `amount` of underlying asset from the reserve, burning the equivalent aTokens owned
     * E.g. User has 100 aUSDC, calls withdraw() and receives 100 USDC, burning the 100 aUSDC
     * @param asset The address of the underlying asset to withdraw
     * @param amount The underlying amount to be withdrawn
     *   - Send the value type(uint256).max in order to withdraw the whole aToken balance
     * @param to Address that will receive the underlying, same as msg.sender if the user
     *   wants to receive it on his own wallet, or a different address if the beneficiary is a
     *   different wallet
     * @return The final amount withdrawn
     **/
    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external override whenNotPaused returns (uint256) {
        uint256 amountToWithdraw = _withdraw(asset, amount, to, false);

        return amountToWithdraw;
    }

    function withdrawETH(uint256 amount, address to) external override whenNotPaused returns (uint256) {
        uint256 amountToWithdraw = _withdraw(WETH, amount, to, true);
        IWETH(WETH).withdraw(amountToWithdraw);
        TribeOneHelper.safeTransferETH(to, amountToWithdraw);
        return amountToWithdraw;
    }

    function _withdraw(
        address asset,
        uint256 amount,
        address to,
        bool isETH
    ) private returns (uint256) {
        DataTypes.ReserveData storage reserve = _reserves[asset];

        address aToken = reserve.aTokenAddress;

        uint256 userBalance = IAToken(aToken).balanceOf(msg.sender);

        uint256 amountToWithdraw = amount;

        if (amount == type(uint256).max) {
            amountToWithdraw = userBalance;
        }

        ValidationLogic.validateWithdraw(
            asset,
            amountToWithdraw,
            userBalance,
            _reserves,
            _addressesProvider.getPriceOracle()
        );

        to = isETH ? address(this) : to;

        uint256 burntAmount = IAToken(aToken).burn(msg.sender, to, amountToWithdraw, reserve.liquidityIndex);

        ITribeOneFundingHakaChef(_addressesProvider.getHakaChef()).withdraw(asset, msg.sender, burntAmount);

        emit Withdraw(asset, msg.sender, to, amountToWithdraw);

        return amountToWithdraw;
    }

    /**
     * @dev Allows users to borrow a specific `amount` of the reserve underlying asset, provided that the borrower
     * already deposited enough collateral, or he was given enough allowance by a credit delegator on the
     * corresponding debt token
     * - E.g. User borrows 100 USDC passing as `onBehalfOf` his own address, receiving the 100 USDC in his wallet
     *   and 100 debt tokens
     * @param asset The address of the underlying asset to borrow
     * @param amount The amount to be borrowed
     * @param user Address of the user who will try to get NFT through TribeOne
     **/
    function borrow(
        address asset,
        uint256 amount,
        uint256 interestRate,
        address user
    ) external override whenNotPaused onlyTribeOne {
        DataTypes.ReserveData storage reserve = _reserves[asset];
        _executeBorrow(ExecuteBorrowParams(asset, user, amount, interestRate, reserve.aTokenAddress));

        TribeOneHelper.safeTransfer(asset, _addressesProvider.getTribeOneAssetGateWay(), amount);
        ITribeOneAssetGateWay(_addressesProvider.getTribeOneAssetGateWay()).refund(user, asset, interestRate, amount);
    }

    function borrowETH(
        uint256 amount,
        uint256 interestRate,
        address user
    ) external override whenNotPaused onlyTribeOne {
        DataTypes.ReserveData storage reserve = _reserves[WETH];

        _executeBorrow(ExecuteBorrowParams(WETH, user, amount, interestRate, reserve.aTokenAddress));

        IWETH(WETH).withdraw(amount);

        ITribeOneAssetGateWay(_addressesProvider.getTribeOneAssetGateWay()).refundETH{value: amount}(
            user,
            interestRate,
            amount
        );
    }

    /**
     * @notice Repays a borrowed `amount` on a specific reserve, burning the equivalent debt tokens owned
     * - E.g. User repays 100 USDC, burning 100 debt tokens of the `user` address
     * @param asset The address of the borrowed underlying asset previously borrowed
     * @param amount The amount to repay
     * - Send the value type(uint256).max in order to repay the whole debt for `asset` on the specific `debtMode`
     * @param user Address of the user who will get his debt reduced/removed.
     * @return The final amount repaid
     **/
    function repay(
        address asset,
        address user,
        uint16 interestRate,
        uint256 amount
    ) external override whenNotPaused returns (uint256) {
        return _repay(asset, interestRate, amount, user);
    }

    function repayETH(
        address user,
        uint16 interestRate,
        uint256 amount
    ) external payable override whenNotPaused returns (uint256) {
        require(msg.value == amount, "Insufficient ETH fund");

        IWETH(WETH).deposit{value: amount}();
        return _repay(WETH, interestRate, amount, user);
    }

    function _repay(
        address asset,
        uint16 interestRate,
        uint256 amount,
        address user
    ) private returns (uint256) {
        DataTypes.ReserveData storage reserve = _reserves[asset];

        uint256 stableDebt = IERC20(reserve.stableDebtTokenAddress).balanceOf(user);

        ValidationLogic.validateRepay(reserve, amount, user, stableDebt);

        address aToken = reserve.aTokenAddress;

        uint256 interestBurnAmount = ((amount * uint256(interestRate)) * INTEREST_BURN_PERCENTAGE) /
            ((10000 + uint256(interestRate)) * 10000);
        uint256 paybackAmount = amount - interestBurnAmount;

        // Fund was already arrived through TribeOne from funding pool
        // Transfer repayment to AToken and BurnManager
        TribeOneHelper.safeTransferFrom(asset, address(this), aToken, paybackAmount);
        // SHould transfer interestBurnAmount to burnManager
        if (interestBurnAmount > 0) {
            TribeOneHelper.safeTransferFrom(
                asset,
                address(this),
                _addressesProvider.getInterestBurnManager(),
                interestBurnAmount
            );
        }

        IStableDebtToken(reserve.stableDebtTokenAddress).burn(user, amount, interestBurnAmount);

        IAToken(aToken).handleRepayment(interestBurnAmount);

        if (stableDebt.sub(paybackAmount) == 0) {
            _usersConfig[user].setBorrowing(reserve.id, false);
        }

        emit Repay(asset, user, msg.sender, paybackAmount);
        return paybackAmount;
    }

    /**
     * @dev Returns the state and configuration of the reserve
     * @param asset The address of the underlying asset of the reserve
     * @return The state of the reserve
     **/
    function getReserveData(address asset) external view override returns (DataTypes.ReserveData memory) {
        return _reserves[asset];
    }

    /**
     * @dev Returns the borrower account data across all the reserves
     * @param user The address of the user
     * @return totalCollateralETH the total collateral in ETH of the user
     * @return totalDebtETH the total debt in ETH of the user
     * @return totalPendingETH the total pending in ETH of the user
     * @return availableBorrowsETH the borrowing power left of the user
     * @return healthFactor the current health factor of the user
     **/
    function getUserAccountData(address user)
        external
        view
        override
        returns (
            uint256 totalCollateralETH,
            uint256 totalDebtETH,
            uint256 totalPendingETH,
            uint256 availableBorrowsETH,
            uint256 healthFactor
        )
    {
        (totalCollateralETH, totalDebtETH, totalPendingETH, healthFactor) = GenericLogic.calculateUserAccountData(
            user,
            _addressesProvider.getCollateralManager(),
            _addressesProvider.getTribeOneAssetGateWay(),
            _reserves,
            _reservesList,
            _reservesCount,
            _addressesProvider.getPriceOracle()
        );

        availableBorrowsETH = GenericLogic.calculateAvailableBorrowsETH(
            totalCollateralETH,
            totalDebtETH + totalPendingETH,
            _borrowHealthFactor
        );
    }

    /**
     * @dev Returns the configuration of the reserve
     * @param asset The address of the underlying asset of the reserve
     * @return The configuration of the reserve
     **/
    function getConfiguration(address asset) external view override returns (DataTypes.ReserveConfigurationMap memory) {
        return _reserves[asset].configuration;
    }

    /**
     * @dev Returns the configuration of the user across all the reserves
     * @param user The user address
     * @return The configuration of the user
     **/
    function getUserConfiguration(address user) external view override returns (DataTypes.UserConfigurationMap memory) {
        return _usersConfig[user];
    }

    /**
     * @dev Returns if the FundingPool is paused
     */
    function paused() external view override returns (bool) {
        return _paused;
    }

    /**
     * @dev Returns the list of the initialized reserves
     **/
    function getReservesList() external view override returns (address[] memory) {
        address[] memory _activeReserves = new address[](_reservesCount);

        for (uint256 i = 0; i < _reservesCount; i++) {
            _activeReserves[i] = _reservesList[i];
        }
        return _activeReserves;
    }

    /**
     * @dev Returns the cached FundingPoolAddressesProvider connected to this contract
     **/
    function getAddressesProvider() external view override returns (ITribeOneAddressesProvider) {
        return _addressesProvider;
    }

    /**
     * @dev Returns the percentage of available liquidity that can be borrowed at once at stable rate
     */
    function MAX_STABLE_RATE_BORROW_SIZE_PERCENT() external view returns (uint256) {
        return _maxStableRateBorrowSizePercent;
    }

    /**
     * @dev Initializes a reserve, activating it, assigning an aToken and debt tokens and an
     * interest rate strategy
     * @param asset The address of the underlying asset of the reserve
     * @param aTokenAddress The address of the aToken that will be assigned to the reserve
     * @param stableDebtAddress The address of the StableDebtToken that will be assigned to the reserve
     * @param hakaAllocPoint the alloc point of asset in HakaChef
     **/
    function initReserve(
        address asset,
        address aTokenAddress,
        address stableDebtAddress,
        uint256 hakaAllocPoint
    ) external override {
        require(Address.isContract(asset), "FP: NOT contract");
        _reserves[asset].init(aTokenAddress, stableDebtAddress);
        uint256 reservesCount = _reservesCount;

        bool reserveAlreadyAdded = _reserves[asset].id != 0 || _reservesList[0] == asset;

        if (!reserveAlreadyAdded) {
            _reserves[asset].id = uint8(reservesCount);
            _reservesList[reservesCount] = asset;

            _reservesCount = reservesCount + 1;

            ITribeOneFundingHakaChef(_addressesProvider.getHakaChef()).add(hakaAllocPoint, asset);
        }
    }

    function setReserveActive(address _asset, bool _active) external {
        DataTypes.ReserveConfigurationMap memory currentConfig = _reserves[_asset].configuration;
        currentConfig.setActive(_active);
        _reserves[_asset].configuration.data = currentConfig.data;
    }

    /**
     * @dev Set the _pause state of a reserve
     * @param val `true` to pause the reserve, `false` to un-pause it
     */
    function setPause(bool val) external override onlyOwner {
        _paused = val;
        if (_paused) {
            emit Paused();
        } else {
            emit Unpaused();
        }
    }

    struct ExecuteBorrowParams {
        address asset;
        address user;
        uint256 amount;
        uint256 interestRate;
        address aTokenAddress;
    }

    /**
     * We can skip validating borrow here because we validated request already
     */
    function _executeBorrow(ExecuteBorrowParams memory vars) internal {
        DataTypes.ReserveData storage reserve = _reserves[vars.asset];
        DataTypes.UserConfigurationMap storage userConfig = _usersConfig[vars.user];

        bool isFirstBorrowing = false;
        isFirstBorrowing = IStableDebtToken(reserve.stableDebtTokenAddress).mint(
            vars.user,
            vars.amount,
            vars.interestRate
        );

        if (isFirstBorrowing) {
            userConfig.setBorrowing(reserve.id, true);
        }

        IAToken(vars.aTokenAddress).transferUnderlyingTo(address(this), vars.amount);

        reserve.updateState(vars.asset);

        emit Borrow(vars.asset, vars.user, vars.amount, vars.interestRate);
    }

    function validateBorrow(
        address asset,
        address user,
        uint256 amount
    ) external view override {
        _validateBorrow(asset, user, amount);
    }

    function validateBorrowETH(address user, uint256 amount) external view override {
        _validateBorrow(WETH, user, amount);
    }

    function _validateBorrow(
        address asset,
        address user,
        uint256 amount
    ) private view {
        DataTypes.ReserveData storage reserve = _reserves[asset];

        address oracle = _addressesProvider.getPriceOracle();
        uint256 amountInETH = IPriceOracle(oracle).getAssetPrice(asset).mul(amount).div(10**18);

        ValidationLogic.validateBorrow(
            asset,
            reserve,
            user,
            amount,
            amountInETH,
            _maxStableRateBorrowSizePercent,
            _borrowHealthFactor,
            _reserves,
            _reservesList,
            _addressesProvider.getCollateralManager(),
            _addressesProvider.getTribeOneAssetGateWay(),
            _reservesCount,
            oracle
        );
    }
}
