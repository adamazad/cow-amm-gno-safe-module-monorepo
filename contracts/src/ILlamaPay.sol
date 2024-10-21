// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

interface ILlamaPay {
  struct LlamaPayStreamParams {
    address from;
    address to;
    uint216 amountPerSec;
  }

  event Withdraw(address from, address to, uint256 amountPerSec, uint256 streamId, uint256 amountToTransfer);

  function withdrawable(address from, address to, uint216 amountPerSec)
    external
    view
    returns (uint256 withdrawableAmount, uint256 lastUpdate, uint256 owed);

  function withdraw(address from, address to, uint216 amountPerSec) external;

  function depositAndCreate(uint256 amountToDeposit, address to, uint216 amountPerSec) external;
}
