// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

interface ISafe {
  /// @dev Allows a Module to execute a Safe transaction without any further confirmations.
  /// @param to Destination address of module transaction.
  /// @param value Ether value of module transaction.
  /// @param data Data payload of module transaction.
  /// @param operation Operation type of module transaction.
  function execTransactionFromModule(address to, uint256 value, bytes calldata data, Enum.Operation operation)
    external
    returns (bool success);
}

/// @title Enum - Collection of enums
/// @author Richard Meissner - <richard@gnosis.pm>
contract Enum {
  enum Operation {
    Call,
    DelegateCall
  }
}
