// SPDX-License-Identifier: MIT
pragma solidity 0.8.0;

/**
 * @dev This token is for testing FundingPool by combining with TribeOne simply
 */

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IFundingPool} from "../fundingPool/interfaces/IFundingPool.sol";
import {ITribeOneAddressesProvider} from "../interfaces/ITribeOneAddressesProvider.sol";
import {ITribeOneAssetGateWay} from "../interfaces/ITribeOneAssetGateWay.sol";
import {TribeOneHelper} from "../libraries/TribeOneHelper.sol";
import "../TribeOneStorage.sol";

import "hardhat/console.sol";

contract TribeOneMock is ReentrancyGuard, TribeOneStorage {
    receive() external payable {}

    function getAddressesProvider() external view returns (ITribeOneAddressesProvider) {
        return _addressesProvider;
    }

    function setAddressesProvider(ITribeOneAddressesProvider _provider) external {
        _addressesProvider = _provider;
    }

    function approveLoan(
        address _token,
        uint256 _amount,
        address _agent,
        address _user,
        uint16 _interest
    ) external nonReentrant {
        if (_token == address(0)) {
            // This function delivers loan amount to this TrieOne smart contract
            ITribeOneAssetGateWay(_addressesProvider.getTribeOneAssetGateWay()).requestETH(_user, _interest, _amount);
            TribeOneHelper.safeTransferETH(_agent, _amount);
        } else {
            // This function delivers loan amount to this TrieOne smart contract
            ITribeOneAssetGateWay(_addressesProvider.getTribeOneAssetGateWay()).request(
                _user,
                _token,
                _interest,
                _amount
            );
            TribeOneHelper.safeTransfer(_token, _agent, _amount);
        }
    }

    function relayNFT(
        address _token,
        uint256 _amount,
        uint256 _interestRate
    ) external payable nonReentrant {
        if (_token == address(0)) {
            IFundingPool(_addressesProvider.getFundingPool()).borrowETH(_amount, _interestRate, msg.sender);
        } else {
            // This function delivers loan amount to this TrieOne smart contract
            IFundingPool(_addressesProvider.getFundingPool()).borrow(_token, _amount, _interestRate, msg.sender);
        }
    }

    function payInstallment(
        address _loanCurrency,
        uint256 _amount,
        uint256 _interestRate
    ) external payable nonReentrant {
        if (_loanCurrency == address(0)) {
            IFundingPool(_addressesProvider.getFundingPool()).repayETH{value: _amount}(
                msg.sender,
                uint16(_interestRate),
                _amount
            );
        } else {
            TribeOneHelper.safeTransferFrom(_loanCurrency, msg.sender, _addressesProvider.getFundingPool(), _amount);
            IFundingPool(_addressesProvider.getFundingPool()).repay(
                _loanCurrency,
                msg.sender,
                uint16(_interestRate),
                _amount
            );
        }
    }
}
