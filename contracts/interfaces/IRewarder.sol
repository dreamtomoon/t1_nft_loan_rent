// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IRewarder {
    function onHakaReward(address to, uint256 amount) external returns (uint256);

    // function pendingTokens(
    //     uint256 pid,
    //     address user,
    //     uint256 hakaAmount
    // ) external view returns (IERC20[] memory, uint256[] memory);
}
