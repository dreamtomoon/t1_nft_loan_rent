// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ITribeOneAddressesProvider} from "../interfaces/ITribeOneAddressesProvider.sol";

/**
 * @title FundingPoolAddressesProvider contract
 * @dev Main registry of addresses part of or connected to the protocol, including permissioned roles
 **/
contract TribeOneAddressesProvider is Ownable, ITribeOneAddressesProvider {
    address private fundingPool;
    address private priceOracle;
    address private collateralManager;
    address private hakaChef;
    address private tribeOne;
    address private tribeOneAssetGateWay;
    address private interestBurnManager;
    address private uniswapV2Router;

    constructor() {}

    /**
     * @dev Returns the address of the FundingPool address
     * @return The FundingPool address
     **/
    function getFundingPool() external view override returns (address) {
        return fundingPool;
    }

    /**
     * @dev Updates the implementation of the FundingPool, or creates the proxy
     * setting the new `pool` implementation on the first time calling it
     * @param pool The new FundingPool implementation
     **/
    function setFundingPool(address pool) external override onlyOwner {
        fundingPool = pool;
        emit FundingPoolUpdated(pool);
    }

    function getPriceOracle() external view override returns (address) {
        return priceOracle;
    }

    function setPriceOracle(address _priceOracle) external override onlyOwner {
        priceOracle = _priceOracle;
        emit PriceOracleUpdated(_priceOracle);
    }

    function getCollateralManager() external view override returns (address) {
        return collateralManager;
    }

    function setCollateralManager(address _collateralManager) external override onlyOwner {
        collateralManager = _collateralManager;
        emit CollateralManagerUpdated(_collateralManager);
    }

    function getHakaChef() external view override returns (address) {
        return hakaChef;
    }

    function setHakaChef(address _hakaChef) external override onlyOwner {
        hakaChef = _hakaChef;
        emit HakaChefUpdated(hakaChef);
    }

    function getTribeOne() external view override returns (address) {
        return tribeOne;
    }

    function setTribeOne(address _tribOne) external override onlyOwner {
        tribeOne = _tribOne;
        emit TribeOneUpdated(_tribOne);
    }

    function getTribeOneAssetGateWay() external view override returns (address) {
        return tribeOneAssetGateWay;
    }

    function setTribeOneAssetGateWay(address _gateway) external override onlyOwner {
        tribeOneAssetGateWay = _gateway;
        emit TribeOneAssetGateWayUpdated(_gateway);
    }

    function getInterestBurnManager() external view override returns (address) {
        return interestBurnManager;
    }

    function setInterestBurnManager(address _burnManager) external override onlyOwner {
        interestBurnManager = _burnManager;
        emit InterestBurnManagerUpdated(_burnManager);
    }

    function getUniswapV2Router() external view override returns (address) {
        return uniswapV2Router;
    }

    function setUniswapV2Router(address _router) external override onlyOwner {
        uniswapV2Router = _router;
        emit UniswapV2RouterUpdated(_router);
    }
}
