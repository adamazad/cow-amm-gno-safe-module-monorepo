// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.25;

interface IERC20 {
  function approve(address spender, uint256 amount) external returns (bool);
  function balanceOf(address account) external view returns (uint256);
  function decimals() external view returns (uint8);
  function totalSupply() external view returns (uint256);
  function symbol() external view returns (string memory);
}
