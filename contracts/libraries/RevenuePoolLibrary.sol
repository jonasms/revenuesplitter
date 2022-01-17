// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

library RevenuePoolLibrary {
    function transferEth(address to_, uint256 value_) internal {
        (bool success, bytes memory data) = to_.call{ value: value_ }("");
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "RevenuePoolLibrary::transferEth: TRANSACTION_FAILED"
        );
    }
}
