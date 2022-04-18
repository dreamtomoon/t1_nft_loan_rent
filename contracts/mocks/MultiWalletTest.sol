// SPDX-License-Identifier: MIT

pragma solidity 0.8.0;

contract MultiWalletTest {
    event NonPayableEvent(address _sender);
    event PayableEvent(address _sender, uint256 _value);

    address public sender;
    uint256 public value;

    constructor() {}

    function nonPayableFunction(address _sender) external {
        sender = _sender;

        emit NonPayableEvent(_sender);
    }

    function payableFunction(address _sender) external payable {
        sender = _sender;
        value = msg.value;
        emit PayableEvent(_sender, value);
    }
}
