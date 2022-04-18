// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IStableDebtToken} from "../../interfaces/IStableDebtToken.sol";
import {WadRayMath} from "../math/WadRayMath.sol";
import {PercentageMath} from "../math/PercentageMath.sol";
import {DataTypes} from "../types/DataTypes.sol";

import "hardhat/console.sol";

/**
 * @title ReserveLogic library
 * @notice Implements the logic to update the reserves state
 */
library ReserveLogic {
    using WadRayMath for uint256;
    using PercentageMath for uint256;

    /**
     * @dev Updates the liquidity cumulative index.
     * @param reserve the reserve object
     * @param asset reserve underlying asset address
     **/
    function updateState(DataTypes.ReserveData storage reserve, address asset) internal {
        uint256 compoundedLiquidity = IERC20(asset).balanceOf(reserve.aTokenAddress) +
            IStableDebtToken(reserve.stableDebtTokenAddress).compoundedTotalSupply();
        uint256 aTokenBalance = IERC20(reserve.aTokenAddress).totalSupply();

        reserve.liquidityIndex = uint128(compoundedLiquidity.rayDiv(aTokenBalance));
    }

    /**
     * @dev Initializes a reserve
     * @param reserve The reserve object
     * @param aTokenAddress The address of the overlying atoken contract
     **/
    function init(
        DataTypes.ReserveData storage reserve,
        address aTokenAddress,
        address stableDebtTokenAddress
    ) internal {
        require(reserve.aTokenAddress == address(0), "Reserve was already initialized");

        reserve.liquidityIndex = uint128(WadRayMath.ray());
        reserve.aTokenAddress = aTokenAddress;
        reserve.stableDebtTokenAddress = stableDebtTokenAddress;
    }
}
