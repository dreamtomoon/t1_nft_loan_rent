// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

/************
@title I interface
@notice Interface for the TribeOne collateral manager.*/
interface ICollateralManager {
    event DepositCollateral(address indexed _user, address indexed _token, uint256 _amount);
    event WithdrawCollateral(address indexed _user, address indexed _token, uint256 _amount);
    event AddCollateralAsset(address indexed _asset);

    function setTribeOne(address _tribeOne) external;

    function getUserCollateralByAsset(address _user, address _asset) external view returns (uint256);

    function getUserCollateralInETH(address _user) external view returns (uint256);

    function depositCollateral(
        address _user,
        address _token,
        uint256 _amount
    ) external;

    function withdrawCollateral(
        address _token,
        address _to,
        uint256 _amount
    ) external;

    function selfLiquidateCollateral(
        address collateralToken,
        address loanToken,
        address user,
        uint256 amountOut
    ) external;
}
