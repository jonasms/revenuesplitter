// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

interface IRevenueSplitter {
    function execute(bytes calldata data_) external;

    // receive() external payable;

    event PaymentReceived(address, uint256);
}
