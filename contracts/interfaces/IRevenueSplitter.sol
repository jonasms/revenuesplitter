// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

interface IRevenueSplitter {
    function balanceOfUnexercised(address account_) external view returns (uint256);

    function deposit() external payable;

    function withdraw() external;

    function withdrawBySig(
        uint256 revenuePeriodDate_,
        uint8 v_,
        bytes32 r_,
        bytes32 s_
    ) external;

    function withdrawBulk(
        uint256[] calldata datesList_,
        uint8[] calldata vList_,
        bytes32[] calldata rList_,
        bytes32[] calldata sList_
    ) external;

    function redeem() external;

    function redeemBySig(
        uint256 revenuePeriodDate_,
        uint8 v_,
        bytes32 r_,
        bytes32 s_
    ) external;

    function redeemBulk(
        uint256[] calldata datesList_,
        uint8[] calldata vList_,
        bytes32[] calldata rList_,
        bytes32[] calldata sList_
    ) external;

    function endPeriod() external;

    function setMaxTokenSupply(uint256 maxTokenSupply_) external;

    function execute(bytes calldata data_) external;

    event Deposit(address indexed account, uint256 amount);

    event Withdraw(address indexed account, uint256 amount);

    event MintRestricted(address indexed account, uint256 amount);

    event Redeem(address indexed account, uint256);

    event StartNewPeriod(uint256 indexed periodId, uint256 periodDate, uint256 periodRevenue);

    event Execute(address indexed target, uint256 value, bytes);

    event PaymentReceived(address, uint256);
}
