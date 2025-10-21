// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {PolicyProtected} from "@chainlink/policy-management/core/PolicyProtected.sol";

/// @title AceStandardERC20
/// @notice Example ERC20 token that demonstrates how to wire PolicyProtected hooks required by Chainlink ACE.
/// @dev This contract keeps the ERC20 API as close as possible to a standard implementation while
///      delegating authorisation logic to the PolicyEngine through the `runPolicy` modifiers.
contract AceStandardERC20 is Initializable, ERC20Upgradeable, PolicyProtected {
  /// @notice Initialises the ERC20 and binds it to an ACE PolicyEngine instance.
  /// @param name_ Token name used by the ERC20 metadata extension.
  /// @param symbol_ Token symbol used by the ERC20 metadata extension.
  /// @param policyEngine Address of the ACE PolicyEngine responsible for evaluating policies.
  /// @param initialOwner Address that becomes the PolicyProtected owner (can manage policies via the engine).
  function initialize(
    string memory name_,
    string memory symbol_,
    address policyEngine,
    address initialOwner
  )
    external
    initializer
  {
    __PolicyProtected_init(initialOwner, policyEngine);
    __ERC20_init(name_, symbol_);
  }

  /// @inheritdoc ERC20Upgradeable
  function transfer(address to, uint256 value) public override runPolicy returns (bool) {
    return super.transfer(to, value);
  }

  /// @inheritdoc ERC20Upgradeable
  function transferFrom(address from, address to, uint256 value) public override runPolicy returns (bool) {
    return super.transferFrom(from, to, value);
  }

  /// @inheritdoc ERC20Upgradeable
  function approve(address spender, uint256 value) public override runPolicy returns (bool) {
    return super.approve(spender, value);
  }

  /// @inheritdoc PolicyProtected
  function supportsInterface(bytes4 interfaceId) public view override(PolicyProtected) returns (bool) {
    return super.supportsInterface(interfaceId);
  }

  /// @notice Simple mint helper gated by ACE policies.
  /// @param to Account receiving the newly minted tokens.
  /// @param amount Amount of tokens to mint.
  function mint(address to, uint256 amount) external runPolicy {
    _mint(to, amount);
  }

  /// @notice Simple burn helper gated by ACE policies.
  /// @param from Account whose tokens will be burned.
  /// @param amount Amount of tokens to burn.
  function burn(address from, uint256 amount) external runPolicy {
    _burn(from, amount);
  }
}
