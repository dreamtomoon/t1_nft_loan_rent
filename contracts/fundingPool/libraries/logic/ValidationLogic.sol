// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReserveLogic} from "./ReserveLogic.sol";
import {GenericLogic} from "./GenericLogic.sol";
import {WadRayMath} from "../math/WadRayMath.sol";
import {PercentageMath} from "../math/PercentageMath.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReserveConfiguration} from "../configuration/ReserveConfiguration.sol";
import {DataTypes} from "../types/DataTypes.sol";

import "hardhat/console.sol";

/**
 * @title ReserveLogic library
 * @notice Implements functions to validate the different actions of the protocol
 */
library ValidationLogic {
    using ReserveLogic for DataTypes.ReserveData;
    using SafeMath for uint256;
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using SafeERC20 for IERC20;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    /**
     * @dev Validates a withdraw action
     * @param reserveAddress The address of the reserve
     * @param amount The amount to be withdrawn
     * @param userBalance The balance of the user
     * @param reservesData The reserves state
     * @param oracle The price oracle
     */
    function validateWithdraw(
        address reserveAddress,
        uint256 amount,
        uint256 userBalance,
        mapping(address => DataTypes.ReserveData) storage reservesData,
        address oracle
    ) internal view {
        require(amount != 0, "Invalid withdraw amount");
        require(amount <= userBalance, "Not enough user balance");

        bool isActive = reservesData[reserveAddress].configuration.getActive();
        require(isActive, "Not active reserve");

        require(
            GenericLogic.balanceDecreaseAllowed(reserveAddress, amount, reservesData, oracle),
            "Withdraw balance not allowed"
        );
    }

    struct ValidateBorrowLocalVars {
        uint256 amountOfCollateralNeededETH;
        uint256 userCollateralBalanceETH;
        uint256 userBorrowBalanceETH;
        uint256 userPendingETH;
        uint256 availableLiquidity;
        uint256 healthFactor;
        bool isActive;
        bool isFrozen;
        bool borrowingEnabled;
    }

    /**
     * @dev Validates a borrow action
     * @param asset The address of the asset to borrow
     * @param reserve The reserve state from which the user is borrowing
     * @param user the user who tries to borrow
     * @param amount The amount to be borrowed
     * @param maxStableLoanPercent The max amount of the liquidity that can be borrowed at stable rate, in percentage
     */
    function validateBorrow(
        address asset,
        DataTypes.ReserveData storage reserve,
        address user,
        uint256 amount,
        uint256 amountInETH,
        uint256 maxStableLoanPercent,
        uint256 borrowHealthFactor,
        mapping(address => DataTypes.ReserveData) storage reservesData,
        mapping(uint256 => address) storage reserves,
        address collateralManager,
        address tribeOneAssetGateWay,
        uint256 reservesCount,
        address oracle
    ) internal view {
        ValidateBorrowLocalVars memory vars;

        (vars.userCollateralBalanceETH, vars.userBorrowBalanceETH, vars.userPendingETH, ) = GenericLogic
            .calculateUserAccountData(
            user,
            collateralManager,
            tribeOneAssetGateWay,
            reservesData,
            reserves,
            reservesCount,
            oracle
        );

        vars.amountOfCollateralNeededETH = vars
            .userBorrowBalanceETH
            .add(vars.userPendingETH)
            .add(amountInETH)
            .mul(borrowHealthFactor)
            .div(10000);

        require(
            vars.amountOfCollateralNeededETH <= vars.userCollateralBalanceETH,
            "Validation: Insufficient collateral"
        );

        /**
         * Following conditions need to be met if the user is borrowing at a stable rate:
         * Users will be able to borrow only a portion of the total available liquidity
         **/
        vars.availableLiquidity = IERC20(asset).balanceOf(reserve.aTokenAddress);

        //calculate the max available loan size in as a percentage of the available liquidity
        uint256 maxLoanSizeStable = vars.availableLiquidity.percentMul(maxStableLoanPercent);

        require(amount <= maxLoanSizeStable, "Validation: Amount bigger than max loan size");
    }

    /**
     * @dev Validates a repay action
     * @param reserve The reserve state from which the user is repaying
     * @param amountSent The amount sent for the repayment. Can be an actual value or uint(-1)
     * @param onBehalfOf The address of the user msg.sender is repaying for
     * @param stableDebt The borrow balance of the user
     */
    function validateRepay(
        DataTypes.ReserveData storage reserve,
        uint256 amountSent,
        address onBehalfOf,
        uint256 stableDebt
    ) internal view {
        bool isActive = reserve.configuration.getActive();

        require(isActive, "VL_NO_ACTIVE_RESERVE");

        require(amountSent > 0, "VL_INVALID_AMOUNT");

        require(stableDebt > 0, "VL_NO_DEBT_OF_SELECTED_TYPE");

        require(
            amountSent != type(uint256).max || msg.sender == onBehalfOf,
            "VL_NO_EXPLICIT_AMOUNT_TO_REPAY_ON_BEHALF"
        );
    }
}
