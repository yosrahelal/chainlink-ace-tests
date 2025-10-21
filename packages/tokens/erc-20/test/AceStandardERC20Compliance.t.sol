// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {IPolicyEngine} from "@chainlink/policy-management/interfaces/IPolicyEngine.sol";
import {IdentityRegistry} from "../../../cross-chain-identity/src/IdentityRegistry.sol";
import {CredentialRegistry} from "../../../cross-chain-identity/src/CredentialRegistry.sol";
import {AceStandardERC20} from "../../erc-20/src/AceStandardERC20.sol";

contract AceStandardERC20ComplianceTest is Test {
  using stdJson for string;

  string internal constant DEFAULT_RPC_URL = "http://127.0.0.1:8545";
  string internal constant DEFAULT_BROADCAST_PATH =
    "./broadcast/DeployAceStandardERC20.s.sol/31337/run-latest.json";

  address internal constant DEFAULT_DEPLOYER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
  address internal constant DEFAULT_TOKEN = 0x68B1D87F95878fE05B998F19b66F4baba5De1aed;
  address internal constant DEFAULT_IDENTITY_REGISTRY = 0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9;
  address internal constant DEFAULT_CREDENTIAL_REGISTRY = 0x5FC8d32690cc91D4c39d9d3abcBD16989F875707;
  address internal constant DEFAULT_IDENTITY_VALIDATOR_POLICY = 0x959922bE3CAee4b8Cd9a407cc3ac1C251C2007B1;
  address internal constant DEFAULT_TOKEN_ADMIN_POLICY = 0xc6e7DF5E7b4f2A278906862b61205850344D4e7d;
  bytes32 internal constant KYC_TYPE = keccak256("common.KYC");

  AceStandardERC20 internal token;
  IdentityRegistry internal identityRegistry;
  CredentialRegistry internal credentialRegistry;
  address internal identityValidatorPolicy;
  address internal tokenAdminPolicy;
  address internal deployer;
  string internal rpcUrl;

  address internal nonCompliantRecipient;
  address internal compliantRecipient;
  uint256 internal forkId;

  function setUp() public {
    _loadDeployment();

    forkId = vm.createFork(rpcUrl);
    vm.selectFork(forkId);

    nonCompliantRecipient = vm.addr(2);
    compliantRecipient = vm.addr(3);

    vm.prank(deployer);
    token.mint(deployer, 10 ether);
  }

  function test_transfer_revertsWithoutKyc() public {
    vm.startPrank(deployer);
    vm.expectRevert(
      abi.encodeWithSelector(
        IPolicyEngine.PolicyRunRejected.selector,
        AceStandardERC20.transfer.selector,
        identityValidatorPolicy,
        "account identity validation failed"
      )
    );
    token.transfer(nonCompliantRecipient, 1 ether);
    vm.stopPrank();
  }

  function test_transfer_succeedsWithKyc() public {
    bytes32 ccid = keccak256(abi.encodePacked("ccid", compliantRecipient, block.timestamp));

    vm.prank(deployer);
    identityRegistry.registerIdentity(ccid, compliantRecipient, "");

    vm.prank(deployer);
    credentialRegistry.registerCredential(ccid, KYC_TYPE, uint40(0), "", "");

    uint256 deployerBalanceBefore = token.balanceOf(deployer);

    vm.prank(deployer);
    token.transfer(compliantRecipient, 1 ether);

    assertEq(token.balanceOf(compliantRecipient), 1 ether, "Recipient should receive transferred tokens");
    assertEq(token.balanceOf(deployer), deployerBalanceBefore - 1 ether, "Deployer balance should decrease");
  }

  function test_mint_revertsForNonOwner() public {
    vm.startPrank(nonCompliantRecipient);
    vm.expectRevert(
      abi.encodeWithSelector(
        IPolicyEngine.PolicyRunRejected.selector,
        AceStandardERC20.mint.selector,
        tokenAdminPolicy,
        "caller is not the policy owner"
      )
    );
    token.mint(nonCompliantRecipient, 1 ether);
    vm.stopPrank();
  }

  function test_mint_succeedsForOwner() public {
    uint256 recipientBalanceBefore = token.balanceOf(compliantRecipient);
    uint256 mintAmount = 2 ether;

    vm.prank(deployer);
    token.mint(compliantRecipient, mintAmount);

    assertEq(token.balanceOf(compliantRecipient), recipientBalanceBefore + mintAmount, "Mint should credit the recipient");
  }

  function _loadDeployment() internal {
    rpcUrl = vm.envOr("RPC_URL", DEFAULT_RPC_URL);

    string memory broadcastPath = vm.envOr("BROADCAST_PATH", DEFAULT_BROADCAST_PATH);
    string memory json;
    bool hasJson;
    if (bytes(broadcastPath).length != 0) {
      try vm.readFile(broadcastPath) returns (string memory contents) {
        json = contents;
        hasJson = true;
      } catch {}
    }

    deployer = vm.envOr("DEPLOYER", DEFAULT_DEPLOYER);

    token = AceStandardERC20(
      _addr("ACE_TOKEN", json, ".transactions[18].contractAddress", hasJson, DEFAULT_TOKEN)
    );
    identityRegistry = IdentityRegistry(
      _addr("ACE_IDENTITY_REGISTRY", json, ".transactions[3].contractAddress", hasJson, DEFAULT_IDENTITY_REGISTRY)
    );
    credentialRegistry = CredentialRegistry(
      _addr(
        "ACE_CREDENTIAL_REGISTRY",
        json,
        ".transactions[5].contractAddress",
        hasJson,
        DEFAULT_CREDENTIAL_REGISTRY
      )
    );
    identityValidatorPolicy = _addr(
      "ACE_IDENTITY_VALIDATOR_POLICY",
      json,
      ".transactions[16].contractAddress",
      hasJson,
      DEFAULT_IDENTITY_VALIDATOR_POLICY
    );
    tokenAdminPolicy = _addr(
      "ACE_TOKEN_ADMIN_POLICY",
      json,
      ".transactions[20].contractAddress",
      hasJson,
      DEFAULT_TOKEN_ADMIN_POLICY
    );
  }

  function _addr(
    string memory envKey,
    string memory json,
    string memory jsonPath,
    bool hasJson,
    address defaultValue
  ) internal returns (address) {
    address env = vm.envOr(envKey, address(0));
    if (env != address(0)) {
      return env;
    }
    if (hasJson) {
      return json.readAddress(jsonPath);
    }
    return defaultValue;
  }
}
