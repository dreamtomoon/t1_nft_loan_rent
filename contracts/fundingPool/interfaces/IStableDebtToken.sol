// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import {IInitializableToken} from "./IInitializableToken.sol";

/**
 * @title IStableDebtToken
 * @notice Defines the interface for the stable debt token
 * @dev It does not inherit from IERC20 to save in code size
 **/

interface IStableDebtToken is IInitializableToken {
    /**
     * @dev Emitted when new stable debt is minted
     * @param user The address of the user who triggered the minting
     * @param amount The amount minted
     * @param interestRate The current balance of the user
     * @param balanceIncrease The increase in balance since the last action of the user
     * @param compoundedIncrease The increase in compounded balance since the last action of the user
     **/
    event Mint(
        address indexed user,
        uint256 amount,
        uint256 interestRate,
        uint256 balanceIncrease,
        uint256 compoundedIncrease
    );

    /**
     * @dev Emitted when new stable debt is burned
     * @param user The address of the user
     * @param amount The amount being burned
     * @param currentBalance The current balance of the user
     **/
    event Burn(address indexed user, uint256 amount, uint256 currentBalance);

    /**
     * @dev Mints debt token to the `onBehalfOf` address.
     * - The resulting rate is the weighted average between the rate of the new debt
     * and the rate of the previous debt
     * @param user The address receiving the borrowed underlying, being the delegatee in case
     * of credit delegate, or same as `onBehalfOf` otherwise
     * @param amount The amount of debt tokens to mint
     * @param rate The rate of the debt being minted
     **/
    function mint(
        address user,
        uint256 amount,
        uint256 rate
    ) external returns (bool);

    /**
     * @dev Burns debt of `user`
     * - The resulting rate is the weighted average between the rate of the new debt
     * and the rate of the previous debt
     * @param user The address of the user getting his debt burned
     * @param amount The amount of debt tokens getting burned
     * @param amountToBurn The amount to burn from interest
     **/
    function burn(
        address user,
        uint256 amount,
        uint256 amountToBurn
    ) external;

    function compoundedTotalSupply() external view returns (uint256);

    function compoundedBalanceOf(address _account) external view returns (uint256);
}
