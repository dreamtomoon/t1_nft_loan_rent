// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IUniswapV2Router01} from "./interfaces/IUniswapV2Router01.sol";
import "./libraries/TribeOneHelper.sol";

contract BurnManager is ReentrancyGuard {
    address public immutable uniRouterAddress;
    address public immutable HAKA;
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    uint256 public slippageFactor = 950; // 5% default slippage tolerance

    event BuyBackHaka(address indexed asset, uint256 assetAmount, uint256 hakaAmount);

    constructor(address _uniRouterAddress, address _HAKA) {
        uniRouterAddress = _uniRouterAddress;
        HAKA = _HAKA;
    }

    function buyBackHaka(address asset, uint256 amount) external nonReentrant {
        uint256 assetBalance = IERC20(asset).balanceOf(address(this));
        require(assetBalance >= amount, "BM: Over flowed amount");

        address[] memory path = new address[](2);
        path[0] = asset;
        path[1] = HAKA;
        _safeSwap(amount, path, address(this));

        uint256 hakaBalance = IERC20(HAKA).balanceOf(address(this));

        TribeOneHelper.safeTransfer(HAKA, BURN_ADDRESS, hakaBalance);
        emit BuyBackHaka(asset, amount, hakaBalance);
    }

    function _safeSwap(
        uint256 _amountIn,
        address[] memory _path,
        address _to
    ) internal {
        if (_amountIn > 0) {
            uint256[] memory amounts = IUniswapV2Router01(uniRouterAddress).getAmountsOut(_amountIn, _path);
            uint256 amountOut = amounts[amounts.length - 1];

            IUniswapV2Router01(uniRouterAddress).swapExactTokensForTokens(
                _amountIn,
                (amountOut * slippageFactor) / 1000,
                _path,
                _to,
                block.timestamp
            );
        }
    }
}
