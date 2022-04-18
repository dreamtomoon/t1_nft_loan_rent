// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

/**
 * @title InterestMath library
 * @notice Provides functions to perform percentage calculations
 * @dev Percentages are defined by default with 2 decimals of precision (100.00). The precision is indicated by PERCENTAGE_FACTOR
 * @dev Operations are rounded half up
 **/

library InterestMath {
    uint256 constant PERCENTAGE_FACTOR = 1e4; //percentage plus two decimals
    uint256 constant HALF_PERCENT = PERCENTAGE_FACTOR / 2;

    /**
     * @dev Executes a interest multiplication
     * @param original The original value
     * @param interest The percentage of interest
     * @return The summing up of original + interest
     **/
    function interestMul(uint256 original, uint256 interest) internal pure returns (uint256) {
        if (original == 0 || interest == 0) {
            return 0;
        }

        return original + (original * interest + HALF_PERCENT) / PERCENTAGE_FACTOR;
    }

    /**
     * @dev Executes a percentage division
     * @param value The value = original + interest
     * @param interest The percentage of the value to be calculated
     * @return The original value
     **/
    function interestDiv(uint256 value, uint256 interest) internal pure returns (uint256) {
        if (interest == 0) {
            return value;
        }

        return (value * PERCENTAGE_FACTOR) / (interest + PERCENTAGE_FACTOR);
    }
}
