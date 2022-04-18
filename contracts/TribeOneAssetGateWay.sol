// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ITribeOneAssetGateWay} from "./interfaces/ITribeOneAssetGateWay.sol";
import {ITribeOneAddressesProvider} from "./interfaces/ITribeOneAddressesProvider.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
import {IFundingPool} from "./fundingPool/interfaces/IFundingPool.sol";
import "./libraries/TribeOneHelper.sol";
import {ValidationLogic} from "./fundingPool/libraries/logic/ValidationLogic.sol";
import {InterestMath} from "./libraries/InterestMath.sol";

import "hardhat/console.sol";

/**
 * @dev This smart contract is the middle man between approving loan and relaying NFT
 */
contract TribeOneAssetGateWay is Ownable, ReentrancyGuard, ITribeOneAssetGateWay {
    using EnumerableSet for EnumerableSet.AddressSet;
    using InterestMath for uint256;

    EnumerableSet.AddressSet private _availableLoanAssets;

    ITribeOneAddressesProvider private _addressesProvider;

    /**
     * @dev This variable shows the fund which was transferred to agent to buy NFT, but not refunded yet
     * asset address => amount
     * address(0) means ETH native coin
     */
    mapping(address => uint256) private _pendingFunds;
    // user => asset  => amount
    mapping(address => mapping(address => uint256)) private _userPendingFunds;

    constructor() {
        // Adding Native coin
        _availableLoanAssets.add(address(0));
    }

    receive() external payable {}

    modifier onlyTribeOne() {
        require(msg.sender == _addressesProvider.getTribeOne(), "Only TribeOne is allowed");
        _;
    }

    function getAddressesProvider() external view returns (address) {
        return address(_addressesProvider);
    }

    function setAddressesProvider(ITribeOneAddressesProvider _provider) external onlyOwner {
        _addressesProvider = _provider;
    }

    function addAvailableLoanAsset(address _asset) external onlyOwner nonReentrant {
        require(!_availableLoanAssets.contains(_asset), "Already available");
        _availableLoanAssets.add(_asset);
        emit AddAvailableLoanAsset(_asset);
    }

    function removeAvailableLoanAsset(address _asset) external onlyOwner nonReentrant {
        require(_availableLoanAssets.contains(_asset), "Asset is not available now");
        _availableLoanAssets.remove(_asset);
        emit RemoveAvailableLoanAsset(_asset);
    }

    function isAvailableLoanAsset(address _asset) external view override returns (bool) {
        return _availableLoanAssets.contains(_asset);
    }

    // TODO
    // Try to check gas fee difference when using struct memory
    function getTotalPendingFundsInETHByUser(address _user) external view override returns (uint256 totalInETH) {
        uint256 len = _availableLoanAssets.length();
        address oracle = _addressesProvider.getPriceOracle();
        address asset;
        uint256 amount;

        for (uint256 ii = 0; ii < len; ii++) {
            asset = _availableLoanAssets.at(ii);
            amount = _userPendingFunds[_user][asset];
            if (amount > 0) {
                totalInETH += asset == address(0)
                    ? amount
                    : (IPriceOracle(oracle).getAssetPrice(asset) * amount) / (10**IERC20Metadata(asset).decimals());
            }
        }
    }

    function getTotalPendingFundsInETH() external view override returns (uint256 totalInETH) {
        uint256 len = _availableLoanAssets.length();
        address oracle = _addressesProvider.getPriceOracle();
        address asset;
        uint256 amount;

        for (uint256 ii = 0; ii < len; ii++) {
            asset = _availableLoanAssets.at(ii);
            amount = _pendingFunds[asset];
            if (amount > 0) {
                totalInETH +=
                    (IPriceOracle(oracle).getAssetPrice(asset) * amount) /
                    (10**IERC20Metadata(asset).decimals());
            }
        }
    }

    /**
     * @dev Tribeone request necessary fund through this function to buy NFT
     * TODO You should take count interest rate here
     */
    function request(
        address _user,
        address _token,
        uint16 _interest,
        uint256 _amount
    ) external override onlyTribeOne {
        uint256 pendingAmount = _amount.interestMul(uint256(_interest));
        IFundingPool(_addressesProvider.getFundingPool()).validateBorrow(_token, _user, pendingAmount);
        _pendingFunds[_token] += pendingAmount;
        _userPendingFunds[_user][_token] += pendingAmount;

        TribeOneHelper.safeTransfer(_token, msg.sender, _amount);
    }

    function requestETH(
        address _user,
        uint16 _interest,
        uint256 _amount
    ) external override onlyTribeOne {
        uint256 pendingAmount = _amount.interestMul(uint256(_interest));
        IFundingPool(_addressesProvider.getFundingPool()).validateBorrowETH(_user, pendingAmount);

        _pendingFunds[address(0)] += pendingAmount;
        _userPendingFunds[_user][address(0)] += pendingAmount;

        TribeOneHelper.safeTransferETH(msg.sender, _amount);
    }

    /**
     * @dev Through this function, the capital which is transferred to agent is refund
     */
    function refund(
        address _user,
        address _token,
        uint256 _interest,
        uint256 _amount
    ) external override {
        address _sender = _msgSender();
        require(
            _sender == _addressesProvider.getTribeOne() || _sender == _addressesProvider.getFundingPool(),
            "Invalid sender"
        );

        uint256 pendingAmount = _amount.interestMul(_interest);

        _pendingFunds[_token] -= pendingAmount;
        _userPendingFunds[_user][_token] -= pendingAmount;
    }

    function refundETH(
        address _user,
        uint256 _interest,
        uint256 _amount
    ) external payable override {
        address _sender = _msgSender();
        require(
            _sender == _addressesProvider.getTribeOne() || _sender == _addressesProvider.getFundingPool(),
            "Invalid sender"
        );
        require(msg.value == _amount, "Wrong refund amount");

        uint256 pendingAmount = _amount.interestMul(_interest);

        _pendingFunds[address(0)] -= pendingAmount;
        _userPendingFunds[_user][address(0)] -= pendingAmount;
    }
}
