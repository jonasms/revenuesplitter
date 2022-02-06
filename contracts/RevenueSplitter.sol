// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./interfaces/IRevenueSplitter.sol";

// TODO remove
import "hardhat/console.sol";

contract RevenueSplitter is ERC20 {
    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 private constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    /// @notice The EIP-712 typehash for the revenue period timestamp used by the contract
    bytes32 private constant REVENUE_PERIOD_DATE_TYPEHASH = keccak256("LastPeriod(uint256 date)");

    uint256 public constant REVENUE_PERIOD_DURATION = 30 days;
    uint256 public constant BLACKOUT_PERIOD_DURATION = 3 days;

    address public owner;
    uint256 public maxTokenSupply;

    struct RestrictedTokenGrant {
        uint256 vestingDate;
        uint256 amount;
        bool exercised;
    }

    mapping(address => RestrictedTokenGrant[]) private _tokenGrants;
    uint256 private _totalSupplyUnexercised;

    uint256 public curPeriodId;

    uint256 private curPeriodDate;
    uint256 private curPeriodRevenue;

    uint256 private lastPeriodDate;
    uint256 private lastPeriodRevenue;
    uint256 private lastPeriodTotalSupply;

    // @dev map revenuePeriodId's to user addresses to the amount of ETH they've withdrawn in the given period
    mapping(uint256 => mapping(address => uint256)) private withdrawlReceipts;

    constructor(
        address owner_,
        uint256 maxTokenSupply_,
        string memory name_,
        string memory symbol_
    ) ERC20(name_, symbol_) {
        owner = owner_;
        maxTokenSupply = maxTokenSupply_;
        uint256 initialPeriodDate = block.timestamp + REVENUE_PERIOD_DURATION;
        curPeriodDate = initialPeriodDate;

        emit StartNewPeriod(0, initialPeriodDate, 0, 0);
    }

    function balanceOfUnexercised(address account_) public view virtual returns (uint256 balanceUnexercised) {
        RestrictedTokenGrant[] storage tokenGrants = _tokenGrants[account_];
        for (uint256 i = 0; i < tokenGrants.length; i++) {
            if (!tokenGrants[i].exercised) {
                balanceUnexercised += tokenGrants[i].amount;
            }
        }
    }

    function _isBlackoutPeriod() internal view returns (bool) {
        uint256 curPeriodStartTime = curPeriodDate - REVENUE_PERIOD_DURATION;
        return BLACKOUT_PERIOD_DURATION >= block.timestamp - curPeriodStartTime;
    }

    // _deposit(address account_, uint amount_) internal virtual
    //  - require deposit amount less than max supply
    //  - calculates amount to mint
    //  - handles transaction fee
    //
    //  - mints or a grant token
    //  - emits event
    function _deposit(address account_, uint256 amount_) internal virtual {
        require(
            totalSupply() + _totalSupplyUnexercised + amount_ <= maxTokenSupply,
            "RevenueSplitter::_deposit: MAX_TOKEN_LIMIT"
        );

        // mint tokens if in first revenue period
        // otherwise, grant restricted tokens
        if (lastPeriodDate == 0) {
            _mint(account_, amount_);
        } else {
            _mintRestricted(account_, amount_, curPeriodId + 2);
        }

        emit Deposit(account_, amount_);
    }

    function deposit() external payable virtual {
        _deposit(msg.sender, msg.value);
    }

    function _withdraw(address account_) internal virtual {
        require(!_isBlackoutPeriod(), "RevenueSplitter::_withdraw: BLACKOUT_PERIOD");
        require(lastPeriodRevenue > 0, "RevenueSplitter::_withdraw: ZERO_REVENUE");

        uint256 withdrawlPower = _getWithdrawlPower(account_);

        require(withdrawlPower > 0, "RevenueSplitter::_withdraw: ZERO_WITHDRAWL_POWER");

        uint256 share = (withdrawlPower * 10**8) / totalSupply();
        uint256 ethShare = share * (lastPeriodRevenue / 10**8);

        withdrawlReceipts[curPeriodId - 1][account_] += withdrawlPower;
        (bool success, bytes memory responseData) = account_.call{ value: ethShare }("");
        if (success) {
            emit Execute(targets[i], values[i], calldatas[i]);
        } else if (returnData.length > 0) {
            // From OZ's Address.sol contract
            assembly {
                let returndata_size := mload(returnData)
                revert(add(32, returnData), returndata_size)
            }
        } else {
            revert("RevenuePool::_withdraw: CALL_REVERTED_WITHOUT_MESSAGE");
        }

        emit Withdraw(account_, withdrawlPower);
    }

    function withdraw() external virtual {
        _withdraw(msg.sender);
    }

    function withdrawBySig(
        uint256 revenuePeriodDate_,
        uint8 v_,
        bytes32 r_,
        bytes32 s_
    ) external {
        require(revenuePeriodDate_ == lastPeriodDate, "RevenueSplitter::withdrawBySig: INVALID_REVENUE_PERIOD_DATE");

        bytes32 domainSeparator = keccak256(
            abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(name())), _getChainId(), address(this))
        );
        bytes32 structHash = keccak256(abi.encode(REVENUE_PERIOD_DATE_TYPEHASH, revenuePeriodDate_));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        address signer = ecrecover(digest, v_, r_, s_);

        require(signer != address(0), "RevenueSplitter::withdrawBySig: INVALID_SIGNATURE");

        _withdraw(signer);
    }

    function withdrawBulk(
        uint256[] calldata datesList_,
        uint8[] calldata vList_,
        bytes32[] calldata rList_,
        bytes32[] calldata sList_
    ) external {
        require(datesList_.length == vList_.length, "RevenueSplitter::withdrawBulk: INFORMATION_ARITY_MISMATCH_V_LIST");
        require(datesList_.length == rList_.length, "RevenueSplitter::withdrawBulk: INFORMATION_ARITY_MISMATCH_R_LIST");
        require(datesList_.length == sList_.length, "RevenueSplitter::withdrawBulk: INFORMATION_ARITY_MISMATCH_S_LIST");

        for (uint256 i = 0; i < vList_.length; i++) {
            address(this).call(
                abi.encodeWithSignature(
                    "withdrawBySig(uint256,uint8,bytes32,bytes32)",
                    datesList_[i],
                    vList_[i],
                    rList_[i],
                    sList_[i]
                )
            );
        }
    }

    function _redeem(address account_) internal virtual {
        RestrictedTokenGrant[] storage tokenGrants = _tokenGrants[account_];

        require(tokenGrants.length > 0, "RevenueSplitter::redeem: ZERO_TOKEN_PURCHASES");

        uint256 exercisedTokensCount;
        for (uint256 i = 0; i < tokenGrants.length; i++) {
            if (tokenGrants[i].vestingDate <= curPeriodId && !tokenGrants[i].exercised) {
                tokenGrants[i].exercised = true;
                exercisedTokensCount += tokenGrants[i].amount;
            }
        }

        require(exercisedTokensCount > 0, "RevenueSplitter::redeem: ZERO_EXERCISABLE_SHARES");

        _totalSupplyUnexercised -= exercisedTokensCount;
        _mint(account_, exercisedTokensCount);

        emit Redeem(account_, exercisedTokensCount);
    }

    function redeem() external virtual {
        _redeem(msg.sender);
    }

    function redeemBySig(
        uint256 revenuePeriodDate_,
        uint8 v_,
        bytes32 r_,
        bytes32 s_
    ) external {
        require(revenuePeriodDate_ == lastPeriodDate, "RevenueSplitter::redeemBySig: INVALID_REVENUE_PERIOD_DATE");

        bytes32 domainSeparator = keccak256(
            abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(name())), _getChainId(), address(this))
        );
        bytes32 structHash = keccak256(abi.encode(REVENUE_PERIOD_DATE_TYPEHASH, revenuePeriodDate_));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        address signer = ecrecover(digest, v_, r_, s_);

        require(signer != address(0), "RevenueSplitter::redeemBySig: INVALID_SIGNATURE");

        _redeem(signer);
    }

    function redeemBulk(
        uint256[] calldata datesList_,
        uint8[] calldata vList_,
        bytes32[] calldata rList_,
        bytes32[] calldata sList_
    ) external {
        require(datesList_.length == vList_.length, "RevenueSplitter::redeemBulk: INFORMATION_ARITY_MISMATCH_V_LIST");
        require(datesList_.length == rList_.length, "RevenueSplitter::redeemBulk: INFORMATION_ARITY_MISMATCH_R_LIST");
        require(datesList_.length == sList_.length, "RevenueSplitter::redeemBulk: INFORMATION_ARITY_MISMATCH_S_LIST");

        for (uint256 i = 0; i < vList_.length; i++) {
            address(this).call(
                abi.encodeWithSignature(
                    "redeemBySig(uint256,uint8,bytes32,bytes32)",
                    datesList_[i],
                    vList_[i],
                    rList_[i],
                    sList_[i]
                )
            );
        }
    }

    function _mintRestricted(
        address account_,
        uint256 amount_,
        uint256 vestingDate_
    ) internal {
        _totalSupplyUnexercised += amount_;
        _tokenGrants[account_].push(RestrictedTokenGrant(vestingDate_, amount_, false));

        emit MintRestricted(account_, amount_);
    }

    function _getWithdrawlPower(address account_) internal view returns (uint256 amount) {
        amount = balanceOf(account_) - withdrawlReceipts[curPeriodId - 1][account_];
    }

    // Prevent tokens from being used for a withdrawl more than once per revenue period
    // Allows transfer of tokens that have been used to withdraw funds in the current period
    function _transfer(
        address to_,
        address from_,
        uint256 amount_
    ) internal virtual override {
        uint256 fromWithdrawnReceipts = withdrawlReceipts[curPeriodId - 1][from_];

        // 0 < withdrawlReceiptTransfer < amount_
        uint256 withdrawlReceiptTransfer = fromWithdrawnReceipts >= amount_ ? amount_ : fromWithdrawnReceipts;

        withdrawlReceipts[curPeriodId - 1][to_] += withdrawlReceiptTransfer;
        withdrawlReceipts[curPeriodId - 1][from_] -= withdrawlReceiptTransfer;

        super._transfer(from_, to_, amount_);
    }

    function _setCurPeriod(uint256 date_, uint256 revenue_) internal {
        curPeriodDate = date_;
        curPeriodRevenue = revenue_;
    }

    function _setLastPeriod(
        uint256 date_,
        uint256 revenue_,
        uint256 totalSupply_
    ) internal {
        lastPeriodDate = date_;
        lastPeriodRevenue = revenue_;
        lastPeriodTotalSupply = totalSupply_;
    }

    function endPeriod() external {
        require(block.timestamp >= curPeriodDate, "RevenueSplitter::endPeriod: REVENUE_PERIOD_IN_PROGRESS");

        _beforeEndPeriod();

        // Write to memory in order to avoid reading from storage more than once
        // Prevent setting `lastPeriodRevenue` to an amount greater than the contract owns
        uint256 endingPeriodRevenue = curPeriodRevenue > address(this).balance
            ? address(this).balance
            : curPeriodRevenue;
        uint256 endingPeriodTotalSupply = totalSupply();
        _setLastPeriod(curPeriodDate, endingPeriodRevenue, endingPeriodTotalSupply);

        uint256 startingPeriodDate = block.timestamp + REVENUE_PERIOD_DURATION;
        uint256 startingPeriodId = curPeriodId + 1;

        _setCurPeriod(startingPeriodDate, endingPeriodRevenue);
        curPeriodId = startingPeriodId;

        _afterEndPeriod();

        emit StartNewPeriod(startingPeriodId, startingPeriodDate, endingPeriodRevenue, endingPeriodTotalSupply);
    }

    function execute(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas
    ) external virtual {
        require(msg.sender == owner, "RevenuePool::execute: ONLY_OWNER");

        for (uint256 i = 0; i < targets.length; i++) {
            (bool success, bytes memory returnData) = targets[i].call{ value: values[i] }(calldatas[i]);
            if (success) {
                emit Execute(targets[i], values[i], calldatas[i]);
            } else if (returnData.length > 0) {
                // From OZ's Address.sol contract
                assembly {
                    let returndata_size := mload(returnData)
                    revert(add(32, returnData), returndata_size)
                }
            } else {
                revert("RevenuePool::execute: CALL_REVERTED_WITHOUT_MESSAGE");
            }
        }
    }

    receive() external payable {
        _onReceive();
        curPeriodRevenue += msg.value;
        emit PaymentReceived(msg.sender, msg.value);
    }

    // TODO setGuardian()

    /* SETTERS */
    function setMaxTokenSupply(uint256 maxTokenSupply_) external virtual {
        require(msg.sender == owner, "RevenuePool::setMaxTokenSupply: ONLY_OWNER");
        maxTokenSupply = maxTokenSupply_;
    }

    /* UTILS */
    function _getChainId() internal view returns (uint256) {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        return chainId;
    }

    /* HOOKS */
    // TODO add params to fxns
    function _beforeTokenUnexercisedTransfer() internal virtual {}

    function _afterTokenUnexercisedTransfer() internal virtual {}

    function _beforeEndPeriod() internal virtual {}

    function _afterEndPeriod() internal virtual {}

    function _onReceive() internal virtual {}

    /* EVENTS */
    event Deposit(address indexed account, uint256 amount);

    event Withdraw(address indexed account, uint256 amount);

    event MintRestricted(address indexed account, uint256 amount);

    event Redeem(address indexed account, uint256);

    event StartNewPeriod(
        uint256 indexed periodId,
        uint256 periodEndDate,
        uint256 periodRevenue,
        uint256 periodTotalSupply
    );

    event Execute(address indexed target, uint256 value, bytes);

    event PaymentReceived(address, uint256);
}
