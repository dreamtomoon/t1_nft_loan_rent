// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import {IFundingPool} from "./IFundingPool.sol";

/**
 * @title IInitializableAToken
 * @notice Interface for the initialize function on AToken
 **/
interface IInitializableToken {
    /**
     * @dev Emitted when an aToken is initialized
     * @param underlyingAsset The address of the underlying asset
     * @param pool The address of the associated lending pool
     * @param tokenDecimals the decimals of the aToken
     * @param tokenName the name of the aToken
     * @param tokenSymbol the symbol of the aToken
     **/
    event Initialized(
        address indexed underlyingAsset,
        address indexed pool,
        uint8 tokenDecimals,
        string tokenName,
        string tokenSymbol
    );

    /**
     * @dev Initializes the aToken
     * @param pool The address of the lending pool where this aToken will be used
     * @param underlyingAsset The address of the underlying asset of this aToken (E.g. WETH for aWETH)
     * @param tokenDecimals The decimals of the aToken, same as the underlying asset's
     * @param tokenName The name of the aToken
     * @param tokenSymbol The symbol of the aToken
     */
    function initialize(
        IFundingPool pool,
        address underlyingAsset,
        uint8 tokenDecimals,
        string calldata tokenName,
        string calldata tokenSymbol
    ) external;
}
