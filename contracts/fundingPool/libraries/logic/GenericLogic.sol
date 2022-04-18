// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReserveLogic} from "./ReserveLogic.sol";
import {ReserveConfiguration} from "../configuration/ReserveConfiguration.sol";
import {UserConfiguration} from "../configuration/UserConfiguration.sol";
import {WadRayMath} from "../math/WadRayMath.sol";
import {PercentageMath} from "../math/PercentageMath.sol";
import {DataTypes} from "../types/DataTypes.sol";
import {IPriceOracle} from "../../../interfaces/IPriceOracle.sol";
import {ICollateralManager} from "../../../interfaces/ICollateralManager.sol";
import {ITribeOneAssetGateWay} from "../../../interfaces/ITribeOneAssetGateWay.sol";

import "hardhat/console.sol";

/**
 * @title GenericLogic library
 * @title Implements protocol-level logic to calculate and validate the state of a user
 */
library GenericLogic {
    using ReserveLogic for DataTypes.ReserveData;
    using SafeMath for uint256;
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using UserConfiguration for DataTypes.UserConfigurationMap;

    uint256 public constant HEALTH_FACTOR_LIQUIDATION_THRESHOLD = 1 ether;

    struct balanceDecreaseAllowedLocalVars {
        uint256 reserveUnderlyingBalance;
        uint256 reserveUtilizedBalance;
        uint256 reserveUnderlyingBalanceinETH;
        uint256 reserveUtilizedBalanceInETH;
    }

    /**
     * @dev Checks if a specific balance decrease is allowed
     * (i.e. doesn't bring the user borrow position health factor under HEALTH_FACTOR_LIQUIDATION_THRESHOLD)
     * @param asset The address of the underlying asset of the reserve
     * @param amount The amount to decrease
     * @param reservesData The data of all the reserves
     * @param oracle The address of the oracle contract
     * @return true if the decrease of the balance is allowed
     **/
    function balanceDecreaseAllowed(
        address asset,
        uint256 amount,
        mapping(address => DataTypes.ReserveData) storage reservesData,
        address oracle
    ) internal view returns (bool) {
        balanceDecreaseAllowedLocalVars memory vars;

        DataTypes.ReserveData storage currentReserve = reservesData[asset];

        vars.reserveUnderlyingBalance = IERC20(asset).balanceOf(currentReserve.aTokenAddress) - amount;
        vars.reserveUtilizedBalance = IERC20(currentReserve.stableDebtTokenAddress).totalSupply();

        // hard coded at the moment
        vars.reserveUnderlyingBalanceinETH = IPriceOracle(oracle)
            .getAssetPrice(asset)
            .mul(vars.reserveUnderlyingBalance)
            .div(10**18);

        vars.reserveUtilizedBalanceInETH = IPriceOracle(oracle)
            .getAssetPrice(asset)
            .mul(vars.reserveUtilizedBalance)
            .div(10**18);

        // TODO should adjust and change final conditions
        return vars.reserveUnderlyingBalanceinETH >= vars.reserveUtilizedBalanceInETH;
    }

    struct CalculateUserAccountDataVars {
        uint256 reserveUnitPrice;
        uint256 tokenUnit;
        uint256 compoundedLiquidityBalance;
        uint256 compoundedBorrowBalance;
        uint256 decimals;
        uint256 i;
        uint256 healthFactor;
        uint256 totalCollateralInETH;
        uint256 totalDebtInETH;
        uint256 totalPendingInETH;
        address currentReserveAddress;
    }

    /**
     * @dev Calculates the user data across the reserves.
     * this includes the total liquidity/collateral/borrow balances in ETH,
     * the average Loan To Value, the average Liquidation Ratio, and the Health factor.
     * @param user The address of the user
     * @param reservesData Data of all the reserves
     * @param reserves The list of the available reserves
     * @param oracle The price oracle address
     * @return The total collateral and total debt of the user in ETH, pending fund of user in ETH, liquidation threshold and the HF
     **/
    function calculateUserAccountData(
        address user,
        address collateralManager,
        address tribeOneAssetGateWay,
        mapping(address => DataTypes.ReserveData) storage reservesData,
        mapping(uint256 => address) storage reserves,
        uint256 reservesCount,
        address oracle
    )
        internal
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        CalculateUserAccountDataVars memory vars;
        for (vars.i = 0; vars.i < reservesCount; vars.i++) {
            vars.currentReserveAddress = reserves[vars.i];
            DataTypes.ReserveData storage currentReserve = reservesData[vars.currentReserveAddress];

            (, , , vars.decimals, ) = currentReserve.configuration.getParams();

            vars.tokenUnit = 10**vars.decimals;
            vars.reserveUnitPrice = IPriceOracle(oracle).getAssetPrice(vars.currentReserveAddress);

            vars.compoundedBorrowBalance = IERC20(currentReserve.stableDebtTokenAddress).balanceOf(user);
            if (vars.compoundedBorrowBalance > 0) {
                vars.totalDebtInETH = vars.totalDebtInETH.add(
                    vars.reserveUnitPrice.mul(vars.compoundedBorrowBalance).div(vars.tokenUnit)
                );
            }
        }

        vars.totalCollateralInETH = ICollateralManager(collateralManager).getUserCollateralInETH(user);

        vars.totalPendingInETH = ITribeOneAssetGateWay(tribeOneAssetGateWay).getTotalPendingFundsInETHByUser(user);

        vars.healthFactor = calculateHealthFactorFromBalances(
            vars.totalCollateralInETH,
            vars.totalDebtInETH + vars.totalPendingInETH
        );
        return (vars.totalCollateralInETH, vars.totalDebtInETH, vars.totalPendingInETH, vars.healthFactor);
    }

    /**
     * @dev Calculates the health factor from the corresponding balances
     * @param totalCollateralInETH The total collateral in ETH
     * @param totalDebtInETH The total debt in ETH
     * @return The health factor calculated from the balances provided
     **/
    function calculateHealthFactorFromBalances(uint256 totalCollateralInETH, uint256 totalDebtInETH)
        internal
        pure
        returns (uint256)
    {
        if (totalDebtInETH == 0) return type(uint256).max;

        return (totalCollateralInETH * 10000) / totalDebtInETH;
    }

    /**
     * @dev Calculates the equivalent amount in ETH that an user can borrow, depending on the available collateral and the
     * @param totalCollateralInETH The total collateral in ETH
     * @param totalDebtInETH The total borrow balance
     * @return the amount available to borrow in ETH for the user
     **/
    function calculateAvailableBorrowsETH(
        uint256 totalCollateralInETH,
        uint256 totalDebtInETH,
        uint256 healthFactor
    ) internal pure returns (uint256) {
        uint256 availableBorrowsETH = totalCollateralInETH.percentDiv(healthFactor);

        if (availableBorrowsETH < totalDebtInETH) {
            return 0;
        }

        availableBorrowsETH = availableBorrowsETH.sub(totalDebtInETH);
        return availableBorrowsETH;
    }
}
