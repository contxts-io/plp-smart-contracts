// SPDX-License-Identifier: MIT

pragma solidity 0.8.3;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";

// loan originator should check if nft has active approvals and promt users to remove approval
// check all approval and approvalforall evnets

contract PineWallet is ERC721EnumerableUpgradeable, OwnableUpgradeable, IERC721Receiver {

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) public pure override returns (bytes4) {
        return
            bytes4(
                keccak256("onERC721Received(address,address,uint256,bytes)")
            );
    }

    mapping (address => bool) collateralizedCollections;

    string private _baseURIextended;

    mapping(address => uint8) private _allowList;

    function _baseURI() internal view virtual override returns (string memory) {
        return _baseURIextended;
    }

    function initialize() public initializer {
      __Ownable_init();
      __ERC721_init("PINEWALLET", "PINEWALLET");
      _baseURIextended = "https://pinewallet-api.pine.loans/meta/";
    }

    function depositCollateral(address target, uint nftID) public onlyOwner {
      ERC721EnumerableUpgradeable(target).transferFrom(msg.sender, address(this), nftID);
      _safeMint(msg.sender, uint(keccak256(abi.encodePacked(target,nftID))));
      collateralizedCollections[target] = true;
    }

    function removeCollateral(address target, uint nftID) public {
      require(ownerOf(uint(keccak256(abi.encodePacked(target,nftID)))) == msg.sender, "wallet is collateralized");
      _burn(uint(keccak256(abi.encodePacked(target,nftID))));
      ERC721EnumerableUpgradeable(target).transferFrom(address(this), msg.sender, nftID);
      if (ERC721EnumerableUpgradeable(target).balanceOf(msg.sender) == 0) collateralizedCollections[target] = false;
    }

    function call(address target, bytes calldata dataContent) public payable onlyOwner {
      require(!collateralizedCollections[target], "cannot operate collateralized assets" );
      (bool success, ) = target.call{value: msg.value}(dataContent);
      require(success);
    }

    function withdraw(uint256 amount) public onlyOwner {
        (bool success, ) = owner().call{value: amount}("");
        require(success, "cannot send ether");
    }

    function recoverSigner(bytes32 _ethSignedMessageHash, bytes memory _signature)
        internal
        pure
        returns (address)
    {
        (bytes32 r, bytes32 s, uint8 v) = splitSignature(_signature);

        return ecrecover(_ethSignedMessageHash, v, r, s);
    }

    function splitSignature(bytes memory sig)
        internal
        pure
        returns (
            bytes32 r,
            bytes32 s,
            uint8 v
        )
    {
        require(sig.length == 65, "invalid signature length");

        assembly {
            /*
            First 32 bytes stores the length of the signature

            add(sig, 32) = pointer of sig + 32
            effectively, skips first 32 bytes of signature

            mload(p) loads next 32 bytes starting at the memory address p into memory
            */

            // first 32 bytes, after the length prefix
            r := mload(add(sig, 32))
            // second 32 bytes
            s := mload(add(sig, 64))
            // final byte (first byte of the next 32 bytes)
            v := byte(0, mload(add(sig, 96)))
        }

        // implicitly return (r, s, v)
    }


  /**
   * @notice Verifies that the signer is the owner of the signing contract.
   */
  function isValidSignature(
    bytes32 _hash,
    bytes calldata _signature
  ) external view returns (bytes4) {
    // Validate signatures
    if ( recoverSigner(_hash, _signature) == owner()) {
      return 0x1626ba7e;
    } else {
      return 0xffffffff;
    }
  }

}