// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

interface ITribeOneAssetGateWay {
    event AddAvailableLoanAsset(address indexed _asset);
    event SetLoanTwapOracle(address _asset, address _twap);
    event RemoveAvailableLoanAsset(address indexed _asset);

    function isAvailableLoanAsset(address _asset) external returns (bool);

    function getTotalPendingFundsInETHByUser(address _user) external view returns (uint256 totalInETH);

    function getTotalPendingFundsInETH() external view returns (uint256 totalInETH);

    function requestETH(
        address _user,
        uint16 _interest,
        uint256 _amount
    ) external;

    function request(
        address _user,
        address _token,
        uint16 _interest,
        uint256 _amount
    ) external;

    function refundETH(
        address _user,
        uint256 _interest,
        uint256 _amount
    ) external payable;

    function refund(
        address _user,
        address _token,
        uint256 _interest,
        uint256 _amount
    ) external;
}
