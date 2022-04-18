// SPDX-License-Identifier: MIT

pragma solidity 0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MockERC20 is Ownable, ERC20 {
    uint256 INITIAL_SUPPLY = 10000000000 * 10**18;

    uint256 public constant faucetLimit = 50000 * 10**18;

    constructor(string memory _name_, string memory _symbol_) ERC20(_name_, _symbol_) {
        _mint(msg.sender, INITIAL_SUPPLY);
    }

    function faucet(uint256 _amount) external {
        require(_amount <= faucetLimit, "Faucet limit error");
        _mint(msg.sender, _amount);
    }
}
