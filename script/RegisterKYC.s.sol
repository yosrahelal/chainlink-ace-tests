// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {IdentityRegistry} from "../packages/cross-chain-identity/src/IdentityRegistry.sol";
import {CredentialRegistry} from "../packages/cross-chain-identity/src/CredentialRegistry.sol";

/// @title RegisterKYC
/// @notice Helper script that onboards a wallet into the ACE stack by registering an identity and a `common.KYC`
/// credential. Requires that the caller owns the Identity & Credential registries administration policy.
contract RegisterKYC is Script {
  bytes32 internal constant COMMON_KYC = keccak256("common.KYC");

  function run() external {
    uint256 adminPrivateKey = vm.envUint("PRIVATE_KEY");
    address account = vm.envAddress("KYC_ACCOUNT");

    address identityRegistryAddr = vm.envAddress("IDENTITY_REGISTRY");
    address credentialRegistryAddr = vm.envAddress("CREDENTIAL_REGISTRY");

    // Allow providing a deterministic CCID via env, otherwise derive from the account.
    bytes32 ccid = _resolveCcid(account);

    IdentityRegistry identityRegistry = IdentityRegistry(identityRegistryAddr);
    CredentialRegistry credentialRegistry = CredentialRegistry(credentialRegistryAddr);

    vm.startBroadcast(adminPrivateKey);

    _registerIdentity(identityRegistry, ccid, account);
    _registerCredential(credentialRegistry, ccid);

    vm.stopBroadcast();

    console.log("--- KYC Registration Complete ---");
    console.log("Account");
    console.logAddress(account);
    console.log("CCID");
    console.logBytes32(ccid);
    console.log("IdentityRegistry");
    console.logAddress(identityRegistryAddr);
    console.log("CredentialRegistry");
    console.logAddress(credentialRegistryAddr);
  }

  function _resolveCcid(address account) internal returns (bytes32) {
    bytes32 provided = vm.envOr("KYC_CCID", bytes32(0));
    if (provided != bytes32(0)) {
      return provided;
    }

    // Optional salt to make the derived CCID deterministic across runs.
    string memory salt = vm.envOr("KYC_CCID_SALT", string(""));
    if (bytes(salt).length > 0) {
      return keccak256(abi.encodePacked(salt));
    }

    return keccak256(abi.encodePacked("ccid:", account));
  }

  function _registerIdentity(IdentityRegistry registry, bytes32 ccid, address account) internal {
    try registry.registerIdentity(ccid, account, "") {
      console.log("Identity registered for account");
    } catch (bytes memory err) {
      // Surface a more readable message when the identity already exists.
      console.log("Identity registration reverted (likely already registered)");
      console.logBytes(err);
    }
  }

  function _registerCredential(CredentialRegistry registry, bytes32 ccid) internal {
    try registry.registerCredential(ccid, COMMON_KYC, uint40(0), "", "") {
      console.log("common.KYC credential registered");
    } catch (bytes memory err) {
      console.log("Credential registration reverted");
      console.logBytes(err);
    }
  }
}
