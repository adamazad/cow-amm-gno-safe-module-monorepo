// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

import {IERC20, IBPool} from "./IBPool.sol";
import {ISafe, Enum} from "./ISafe.sol";
import {BNum} from "./libs/BNum.sol";
import {ILlamaPay} from "./ILlamaPay.sol";

/// @title JoinPoolModule
/// @notice This contract is used to join a pool and transfer the LP tokens to the recipient
contract JoinPoolModule {
  /// @dev BCowPool (50-GNO/50-SAFE) pool address
  address public immutable POOL = 0xAD58D2Bc841Cb8e4f8717Cb21e3FB6c95DCBc286;
  /// @dev The Safe account contract address
  address public safe;
  /// @dev The address that will receive the LP tokens, can be address(0)
  address public lpTokenRecipient;
  /// @dev The LlamaPay contract address
  address public llamaPay;
  /// @dev The LlamaPay stream params, passed to the LlamaPay contract
  ILlamaPay.LlamaPayStreamParams public llamaPayStreamParams;

  struct Call {
    address to;
    uint256 value;
    bytes data;
    Enum.Operation operation;
  }

  error InvalidLlamaPayStreamParamsError();
  error CallError(address to, uint256 value, bytes data, Enum.Operation operation);

  /// @notice Constructor
  /// @param safe_ The Safe account contract address
  /// @param lpTokenRecipient_ The address that will receive the LP tokens
  /// @param llamaPay_ The LlamaPay contract address
  /// @param llamaPayStreamParams_ The LlamaPay stream params: from, to, amountPerSec.
  /// @dev The from address is the LlamaPay contract address, the to address is the Safe account address,
  /// and the amountPerSec is the amount of tokens to stream per second.
  constructor(
    address safe_,
    address lpTokenRecipient_,
    address llamaPay_,
    ILlamaPay.LlamaPayStreamParams memory llamaPayStreamParams_
  ) {
    // Validate the LlamaPay stream params
    if (llamaPayStreamParams_.to != safe_) {
      revert InvalidLlamaPayStreamParamsError();
    }

    safe = safe_;

    lpTokenRecipient = lpTokenRecipient_;
    llamaPay = llamaPay_;
    llamaPayStreamParams = llamaPayStreamParams_;
  }

  /// @notice Claims the LlamaPay stream to the Safe account
  /// @dev This function is used to claim the LlamaPay stream and transfer the tokens to the recipient
  function withdrawLlamaPayStream() public {
    bytes memory data = abi.encodeWithSelector(
      ILlamaPay.withdraw.selector, llamaPayStreamParams.from, llamaPayStreamParams.to, llamaPayStreamParams.amountPerSec
    );
    // Call the LlamaPay contract to claim the stream
    bool success = ISafe(safe).execTransactionFromModule(llamaPay, 0, data, Enum.Operation.Call);

    if (!success) {
      revert CallError(llamaPay, 0, data, Enum.Operation.Call);
    }
  }

  /// @notice Joins a pool
  /// @dev It finds the token with the lowest balance in the Safe account,
  /// calculates the proportional amounts of all tokens,
  /// and finally joins the pool with the calculated amounts.
  function joinPool() public {
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

    // Calculate the proportional amounts ratio based on the lowest balance in Safe account
    uint256 proportionalAmountsRatio =
      _divDownFixed(safeLowestTokenAmountBalance, poolTokensWithBptBalances[safeLowestTokenAmountIndex]);

    // Calculate the proportional amounts for all tokens plus the BPT
    uint256[] memory proportionalAmountsWithBpt = new uint256[](poolTokensWithBptBalances.length);
    for (uint256 i = 0; i < proportionalAmountsWithBpt.length; i++) {
      proportionalAmountsWithBpt[i] = (poolTokensWithBptBalances[i] * proportionalAmountsRatio) / 1e18;
    }

    // BPT amount and poolAmountOut math, ported from the balancer sdk
    uint256 bptAmount = proportionalAmountsWithBpt[proportionalAmountsWithBpt.length - 1];
    uint256 bptAmountReferenceBalance = poolTokensWithBptBalances[poolTokensWithBptBalances.length - 1];
    uint256 bptRatio = BNum.bdiv(bptAmount, bptAmountReferenceBalance);

    // Calls to execute: approvals + join pool
    Call[] memory calls = new Call[](poolTokens.length + 1);

    // Map the proportional amounts to the max amounts in for the pool token (excluding the BPT)
    uint256[] memory maxAmountsIn = new uint256[](poolTokens.length);
    for (uint256 i = 0; i < maxAmountsIn.length; i++) {
      maxAmountsIn[i] = proportionalAmountsWithBpt[i];
    }

    // Approve the pool to spend the tokens from the safe
    for (uint256 i = 0; i < poolTokens.length; i++) {
      calls[i] = buildApproveTokenCall(poolTokens[i], POOL, maxAmountsIn[i]);
    }

    // Join the pool with 99.99% of the BPT amount
    // sending the exact amount of BPT reverts with BPool_TokenAmountInAboveMaxAmountIn error
    uint256 poolAmountOut = (BNum.bmul(bptAmountReferenceBalance, bptRatio) * 9999) / 10_000;

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

  /// @notice Transfers the LP tokens to the canonical recipient
  /// @dev This function is used to transfer the LP tokens to the canonical recipient
  function transferLpTokensToRecipient() public returns (bool success, uint256 amount) {
    // If the recipient is the zero address, do nothing
    if (lpTokenRecipient == address(0)) {
      return (false, 0);
    }

    // Get the Safe's LP token balance
    amount = IERC20(POOL).balanceOf(address(safe));
    // Transfer the LP tokens to the recipient
    Call memory call = Call({
      to: POOL,
      value: 0,
      data: abi.encodeWithSelector(IERC20.transfer.selector, lpTokenRecipient, amount),
      operation: Enum.Operation.Call
    });

    // Execute the transfer
    success = ISafe(safe).execTransactionFromModule(call.to, call.value, call.data, call.operation);

    if (!success) {
      revert CallError(call.to, call.value, call.data, call.operation);
    }

    return (true, amount);
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
