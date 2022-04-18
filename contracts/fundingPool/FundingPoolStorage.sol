// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import {UserConfiguration} from "./libraries/configuration/UserConfiguration.sol";
import {ReserveConfiguration} from "./libraries/configuration/ReserveConfiguration.sol";
import {ReserveLogic} from "./libraries/logic/ReserveLogic.sol";
import {ITribeOneAddressesProvider} from "../interfaces/ITribeOneAddressesProvider.sol";
import {DataTypes} from "./libraries/types/DataTypes.sol";

contract FundingPoolStorage {
    using ReserveLogic for DataTypes.ReserveData;
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using UserConfiguration for DataTypes.UserConfigurationMap;

    ITribeOneAddressesProvider internal _addressesProvider;

    mapping(address => DataTypes.ReserveData) internal _reserves;
    mapping(address => DataTypes.UserConfigurationMap) internal _usersConfig;

    // the list of the available reserves, structured as a mapping for gas savings reasons
    mapping(uint256 => address) internal _reservesList;

    uint256 internal _reservesCount;

    bool internal _paused;

    uint256 internal _maxStableRateBorrowSizePercent;
}
