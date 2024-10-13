// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {MockSafe} from "./MockSafe.sol";
import {JoinPoolModule} from "../src/JoinPoolModule.sol";
import {IBPool} from "../src/IBPool.sol";

contract JoinPoolModuleTest is Test {
  /// @dev GNO contract address
  address public immutable GNO = 0x9C58BAcC331c9aa871AFD802DB6379a98e80CEdb;
  /// @dev Safe contract address
  address public immutable SAFE = 0x4d18815D14fe5c3304e87B3FA18318baa5c23820;
  /// @dev BCowPool address
  address public immutable POOL = 0xAD58D2Bc841Cb8e4f8717Cb21e3FB6c95DCBc286;

  JoinPoolModule public joinPoolModule;
  MockSafe public mockSafe;

  function setUp() public {
    // Create a fork of the gnosis chain
    vm.createSelectFork(vm.rpcUrl("https://rpc.gnosischain.com"));

    mockSafe = new MockSafe();
    joinPoolModule = new JoinPoolModule();

    mockSafe.enableModule(address(joinPoolModule));
  }

  function test_joinPool() public {
    // Mint some SAFE and GNO to the mockSafe
    deal(SAFE, address(mockSafe), 200 ether);
    deal(GNO, address(mockSafe), 0.1 ether);

    // Join the pool
    joinPoolModule.joinPool(address(mockSafe));

    // Check the balance of the pool
    uint256 poolBalance = IBPool(POOL).balanceOf(address(mockSafe));

    emit log_named_uint("safe pool balance", poolBalance);
  }
}
