// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ICollateralManager} from "./interfaces/ICollateralManager.sol";
import {IFundingPool} from "./fundingPool/interfaces/IFundingPool.sol";
import {ITribeOneAddressesProvider} from "./interfaces/ITribeOneAddressesProvider.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
import {IUniswapV2Router01} from "./interfaces/IUniswapV2Router01.sol";
import {TribeOneHelper} from "./libraries/TribeOneHelper.sol";

contract CollateralManager is Ownable, ICollateralManager {
    using EnumerableSet for EnumerableSet.AddressSet;

    mapping(address => bool) private availableCollateralAsset;

    address public tribeOne;
    ITribeOneAddressesProvider private _addressesProvider;

    mapping(address => bool) public isCollateralAsset;
    address[] public collateralAssets;

    EnumerableSet.AddressSet private _collateralAssets;

    // TODO update it with EnumerableMap
    mapping(address => mapping(address => uint256)) private userCollaterals; // user address => collateral => amount;

    uint256 public collateralHealthFactor = 150;

    constructor() {}

    modifier onlyTribeOne() {
        require(msg.sender == _addressesProvider.getTribeOne(), "Only TribeOne contract is allowed");
        _;
    }

    function getAddressesProvider() external view returns (address) {
        return address(_addressesProvider);
    }

    function setAddressesProvider(ITribeOneAddressesProvider _provider) external onlyOwner {
        _addressesProvider = _provider;
    }

    function setTribeOne(address _tribeOne) external override onlyOwner {
        tribeOne = _tribeOne;
    }

    function addCollateral(address _collateral) external onlyOwner {
        require(!_collateralAssets.contains(_collateral), "Already available collateral");
        _collateralAssets.add(_collateral);

        emit AddCollateralAsset(_collateral);
    }

    function depositCollateral(
        address _user,
        address _token,
        uint256 _amount
    ) external override {
        require(_collateralAssets.contains(_token), "Token is not allowed for collateral");
        TribeOneHelper.safeTransferFrom(_token, msg.sender, address(this), _amount);

        userCollaterals[_user][_token] += _amount;

        emit DepositCollateral(_user, _token, _amount);
    }

    function withdrawCollateral(
        address _token,
        address _to,
        uint256 _amount
    ) external override {
        require(userCollaterals[msg.sender][_token] >= _amount, "CM: Exceeded user's current amount");
        if (_collateralAssets.contains(_token)) {
            uint256 amountInETH = (_amount * IPriceOracle(_addressesProvider.getPriceOracle()).getAssetPrice(_token)) /
                (10**IERC20Metadata(_token).decimals());

            (uint256 totalCollateralETH, uint256 totalDebtETH, uint256 totalPendingETH, , ) = IFundingPool(
                _addressesProvider.getFundingPool()
            ).getUserAccountData(msg.sender);

            uint256 borrowHealthFactor = IFundingPool(_addressesProvider.getFundingPool()).borrowHealthFactor();

            uint256 amountOfCollateralNeededETH = ((totalDebtETH + totalPendingETH) * 10000) / borrowHealthFactor;

            require(totalCollateralETH - amountInETH >= amountOfCollateralNeededETH, "CM: Invalid amount");
        }

        TribeOneHelper.safeTransfer(_token, _to, _amount);

        emit WithdrawCollateral(_to, _token, _amount);
    }

    function getUserCollateralByAsset(address _user, address _asset) external view override returns (uint256) {
        return userCollaterals[_user][_asset];
    }

    function getUserCollateralInETH(address _user) public view override returns (uint256) {
        uint256 len = _collateralAssets.length();
        uint256 totalCollateralInETH;
        address _collateralAsset;
        uint256 _collateralAmount;
        address oracle = _addressesProvider.getPriceOracle();

        for (uint256 ii = 0; ii < len; ii++) {
            _collateralAsset = _collateralAssets.at(ii);
            _collateralAmount = userCollaterals[_user][_collateralAsset];
            if (_collateralAmount > 0) {
                totalCollateralInETH +=
                    (_collateralAmount * IPriceOracle(oracle).getAssetPrice(_collateralAsset)) /
                    (10**IERC20Metadata(_collateralAsset).decimals());
            }
        }

        return totalCollateralInETH;
    }

    function selfLiquidateCollateral(
        address collateralToken,
        address loanToken,
        address user,
        uint256 amountOut
    ) external override onlyTribeOne {
        address[] memory path = new address[](2);
        path[0] = collateralToken;
        path[1] = loanToken;
        uint256 amountIn = _safeSwapCollateral(amountOut, path, user, msg.sender);

        userCollaterals[user][collateralToken] -= amountIn;
    }

    function _safeSwapCollateral(
        uint256 _amountOut,
        address[] memory _path,
        address _from,
        address _to
    ) internal returns (uint256) {
        if (_amountOut > 0) {
            uint256[] memory amounts = IUniswapV2Router01(_addressesProvider.getUniswapV2Router())
                .swapTokensForExactTokens(_amountOut, userCollaterals[_from][_path[0]], _path, _to, block.timestamp);
            return amounts[0];
        }
        return 0;
    }
}
