// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract RevenueSplitter is ERC20 {
    address guardian;

    /**
        An extensible base contract for receiving and splitting revenues.

        The base contract:
            - is an ERC20 token
            - can queue and execute arbitrary calls, ostensibly for investing and liquidating funds
                - can be customized by an extending contract (i.e. requirements, such as a threshold of positive votes)
                - queued proposals can be executed by anyone once they reach their eta
            - has a mechanism by which token owners can withdraw
                - by default, can withdraw according to their share of the totalTokens owned
                - needs to be a way to reset the withdraw period

        [Extension contract]
            - has a schedule by which funds are made available for withdrawl


    
     */

    constructor(address guardian_) ERC20("Test", "TST") {
        guardian = guardian_;
    }

    function deposit() external payable {
        deposit(msg.sender);
    }

    function deposit(address to_) public payable {
        // calculate tokens to transfer given ETH received
        // _mint tokens to sender
    }

    // function queue()

    function _execute(bytes calldata data_) internal virtual {
        require(msg.sender == guardian, "RevenueSharing::execute: GUARDIAN_ONLY");
        // execute call
        // return call result
    }

    function execute(bytes calldata data_) external {
        _beforeExecute(data_);

        // TODO throw on call failure?
        _execute(data_);

        _afterExecute(data_);
    }

    // function withdraw()
    // function withdraw(address receiver_)
    // _beforeWithdraw(address receiver_, uint amount_) + _afterWithdraw(address receiver_, uint amount_)

    receive() external payable {
        emit PaymentReceived(msg.sender, msg.value);
    }

    // setGuardian()

    /* HOOKS */
    function _beforeExecute(bytes calldata data_) internal virtual {}

    function _afterExecute(bytes calldata data_) internal virtual {}

    event PaymentReceived(address, uint256);
}
