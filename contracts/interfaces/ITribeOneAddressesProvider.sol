// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

/**
 * @title ITribeOneAddressesProvider contract
 * @dev Main registry of addresses part of or connected to the protocol, including permissioned roles
 **/
interface ITribeOneAddressesProvider {
    event FundingPoolUpdated(address indexed newAddress);
    event PriceOracleUpdated(address indexed newAddress);
    event CollateralManagerUpdated(address indexed collateralManager);
    event HakaChefUpdated(address indexed hakaChef);
    event TribeOneUpdated(address indexed tribOne);
    event TribeOneAssetGateWayUpdated(address indexed gateway);
    event InterestBurnManagerUpdated(address indexed _burnManager);
    event UniswapV2RouterUpdated(address indexed _router);

    function getFundingPool() external view returns (address);

    function setFundingPool(address pool) external;

    function getPriceOracle() external view returns (address);

    function setPriceOracle(address priceOracle) external;

    function getCollateralManager() external view returns (address);

    function setCollateralManager(address _collateralManager) external;

    function getHakaChef() external view returns (address);

    function setHakaChef(address _hakaChef) external;

    function getTribeOne() external view returns (address);

    function setTribeOne(address _tribOne) external;

    function getTribeOneAssetGateWay() external view returns (address);

    function setTribeOneAssetGateWay(address _gateway) external;

    function getInterestBurnManager() external view returns (address);

    function setInterestBurnManager(address _burnManager) external;

    function getUniswapV2Router() external view returns (address);

    function setUniswapV2Router(address _router) external;
}
