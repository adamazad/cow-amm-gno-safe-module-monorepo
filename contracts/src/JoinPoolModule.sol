// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import {console} from "forge-std/console.sol";
import {IERC20, IBPool} from "./IBPool.sol";
import {ISafe, Enum} from "./ISafe.sol";

contract JoinPoolModule {
  /// @dev GNO contract address
  address public immutable GNO = 0x9C58BAcC331c9aa871AFD802DB6379a98e80CEdb;
  /// @dev Safe contract address
  address public immutable SAFE = 0x4d18815D14fe5c3304e87B3FA18318baa5c23820;
  /// @dev BCowPool (50-GNO/50-SAFE) pool address
  address public immutable POOL = 0xAD58D2Bc841Cb8e4f8717Cb21e3FB6c95DCBc286;

  struct Call {
    address to;
    uint256 value;
    bytes data;
    Enum.Operation operation;
  }

  error CallError(address to, uint256 value, bytes data, Enum.Operation operation);

  /// @notice Joins a pool
  /// @param safe The Safe account contract address
  function joinPool(address safe) public {
    // Fetches the final tokens of the pool and their balances
    address[] memory poolTokens = IBPool(POOL).getFinalTokens();

    // Pool token balances + 1 for the BPT
    uint256[] memory poolTokensWithBptBalances = new uint256[](poolTokens.length + 1);

    // Safe account token balances
    uint256[] memory safeTokenBalances = new uint256[](poolTokens.length);

    // Populate pool and safe token balances
    for (uint256 i = 0; i < poolTokens.length; i++) {
      address token = poolTokens[i];

      poolTokensWithBptBalances[i] = IERC20(token).balanceOf(POOL);
      safeTokenBalances[i] = IERC20(token).balanceOf(safe);
    }

    // Add the pool BPT balance to the pool token balances
    poolTokensWithBptBalances[poolTokensWithBptBalances.length - 1] = IBPool(POOL).totalSupply();

    // Find the token with the lowest balance in the Safe account, this will be the limiting factor
    uint256 safeLowestTokenAmountIndex;
    uint256 safeLowestTokenAmountBalance;
    for (uint256 i = 0; i < safeTokenBalances.length; i++) {
      if (safeLowestTokenAmountBalance == 0 || safeTokenBalances[i] < safeLowestTokenAmountBalance) {
        safeLowestTokenAmountIndex = i;
        safeLowestTokenAmountBalance = safeTokenBalances[i];
      }
    }

    console.log("referenceTokenBalance", safeLowestTokenAmountBalance);
    console.log("poolTokenBalances[referenceTokenIndex]", poolTokensWithBptBalances[safeLowestTokenAmountIndex]);
    console.log("safeTokenBalances[referenceTokenIndex]", safeTokenBalances[safeLowestTokenAmountIndex]);

    // Calculate the proportional amounts ratio based on the lowest balance in Safe account
    uint256 proportionalAmountsRatio =
      _divDownFixed(safeLowestTokenAmountBalance, poolTokensWithBptBalances[safeLowestTokenAmountIndex]);

    console.log("proportionalAmountsRatio", proportionalAmountsRatio);

    // Calculate the proportional amounts for all tokens plus the BPT
    uint256[] memory proportionalAmountsWithBpt = new uint256[](poolTokensWithBptBalances.length);
    for (uint256 i = 0; i < proportionalAmountsWithBpt.length; i++) {
      proportionalAmountsWithBpt[i] = (poolTokensWithBptBalances[i] * proportionalAmountsRatio) / 1e18;

      // Debug
      console.log("proportionalAmounts[i]", i, proportionalAmountsWithBpt[i]);
    }

    // BPT amount and poolAmountOut math, ported from the balancer sdk
    uint256 bptAmount = proportionalAmountsWithBpt[proportionalAmountsWithBpt.length - 1];
    uint256 bptAmountReferenceBalance = poolTokensWithBptBalances[poolTokensWithBptBalances.length - 1];
    uint256 bptRatio = BNum.bdiv(bptAmount, bptAmountReferenceBalance);

    console.log("bptAmount", bptAmount);
    console.log("bptAmountReferenceBalance", bptAmountReferenceBalance);
    console.log("bptRatio", bptRatio);

    // Calls to execute
    Call[] memory calls = new Call[](poolTokens.length + 1);

    // Map the proportional amounts to the max amounts in for the pool token (excluding the BPT)
    uint256[] memory maxAmountsIn = new uint256[](poolTokens.length);
    for (uint256 i = 0; i < maxAmountsIn.length; i++) {
      maxAmountsIn[i] = proportionalAmountsWithBpt[i];
      console.log("maxAmountsIn[i]", i, maxAmountsIn[i]);
    }

    // Approve the pool to spend the tokens from the safe
    for (uint256 i = 0; i < poolTokens.length; i++) {
      calls[i] = buildApproveTokenCall(poolTokens[i], POOL, maxAmountsIn[i]);
    }

    // Join the pool
    // add 0.01% slippage
    uint256 poolAmountOut = (BNum.bmul(bptAmountReferenceBalance, bptRatio) * 9999) / 10_000;

    console.log("poolAmountOut", poolAmountOut);

    // Add the join pool call, last in the array
    calls[calls.length - 1] = buildJoinPoolCall(POOL, poolAmountOut, maxAmountsIn);

    // Execute everything
    for (uint256 i = 0; i < calls.length; i++) {
      bool success =
        ISafe(safe).execTransactionFromModule(calls[i].to, calls[i].value, calls[i].data, calls[i].operation);

      if (!success) {
        revert CallError(calls[i].to, calls[i].value, calls[i].data, calls[i].operation);
      }
    }
  }

  /// @dev Builds a join pool call
  /// @param poolAmountOut the amount of pool shares to mint
  /// @param maxAmountsIn the maximum amounts of each token to send to the pool
  /// @return The call
  function buildJoinPoolCall(address pool, uint256 poolAmountOut, uint256[] memory maxAmountsIn)
    public
    pure
    returns (Call memory)
  {
    return Call({
      to: pool,
      value: 0,
      data: abi.encodeWithSelector(IBPool.joinPool.selector, poolAmountOut, maxAmountsIn),
      operation: Enum.Operation.Call
    });
  }

  /// @notice Builds an approve call
  /// @param token The token address
  /// @param spender The spender address
  /// @param amount The amount
  /// @return The call
  function buildApproveTokenCall(address token, address spender, uint256 amount) public pure returns (Call memory) {
    return Call({
      to: token,
      value: 0,
      data: abi.encodeWithSelector(IERC20.approve.selector, spender, amount),
      operation: Enum.Operation.Call
    });
  }

  function _divDownFixed(uint256 a, uint256 b) internal pure returns (uint256) {
    return (a * 1e18) / b;
  }
}

/// @dev BNum library from https://github.com/balancer/cow-amm/blob/04c915d1ef6150b5334f4b69c7af7ddd59e050e2/src/contracts/BNum.sol#L107
library BNum {
  error BNum_DivZero();
  error BNum_DivInternal();
  error BNum_MulOverflow();

  uint256 constant BONE = 1e18;

  function bmul(uint256 a, uint256 b) internal pure returns (uint256) {
    unchecked {
      uint256 c0 = a * b;
      if (a != 0 && c0 / a != b) {
        revert BNum_MulOverflow();
      }
      // NOTE: using >> 1 instead of / 2
      uint256 c1 = c0 + (BONE >> 1);
      if (c1 < c0) {
        revert BNum_MulOverflow();
      }
      uint256 c2 = c1 / BONE;
      return c2;
    }
  }

  function bdiv(uint256 a, uint256 b) internal pure returns (uint256) {
    unchecked {
      if (b == 0) {
        revert BNum_DivZero();
      }
      uint256 c0 = a * BONE;
      if (a != 0 && c0 / a != BONE) {
        revert BNum_DivInternal(); // bmul overflow
      }
      // NOTE: using >> 1 instead of / 2
      uint256 c1 = c0 + (b >> 1);
      if (c1 < c0) {
        revert BNum_DivInternal(); //  badd require
      }
      uint256 c2 = c1 / b;
      return c2;
    }
  }
}
