// SPDX-License-Identifier: MIT

pragma solidity 0.8.0;

interface ITribeOneFundingHakaChef {
    function add(uint256 allocPoint, address _asset) external;

    function deposit(
        uint256 amount,
        address _asset,
        address to
    ) external;

    function withdraw(
        address _asset,
        address _to,
        uint256 amount
    ) external;
}
