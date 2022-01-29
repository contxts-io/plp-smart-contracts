const ERC721 = artifacts.require("Doodles")
const PineWallet = artifacts.require("PineWallet")
const fs = require('fs');
const nftabi = JSON.parse(fs.readFileSync('./build/contracts/IERC721.json', 'utf8'));
const BN = require('bn.js');
const { assert } = require('console');


contract("Pine Wallet", async accounts => {
    /*
    9123ad2f6b0668bf0eb604be9d5751c0a91b8ca38dd2959c3eda8f510516a9de: lender
    accounts[1]: borrower

    */
  before(async () => {
    nft = await ERC721.new()
    nft2 = await ERC721.new()
    await nft.setSaleState(true)
    await nft2.setSaleState(true)
    await nft.mint(5, {value: 1000000000000000000})
    await nft2.mint(5, {value: 1000000000000000000})
    wallet = await PineWallet.new()
    await wallet.initialize()
    await nft.setApprovalForAll(wallet.address, true)
    await nft2.safeTransferFrom(accounts[0], wallet.address, 4)
    nft2contract = new web3.eth.Contract(nftabi.abi)
  })

  it("should withdraw airdropped NFTs", async () => {
    await wallet.call(nft2.address, nft2contract.methods.safeTransferFrom(wallet.address, accounts[0], 4).encodeABI())
    console.log(await nft2.ownerOf(4), accounts[0])
  })

  it("should collateralize NFTs", async () => {
    await wallet.depositCollateral(nft.address, 3)
    console.log(await nft.ownerOf(3), accounts[0])
    
  })

  it("should not operate collateralized NFTs", async () => {
    try{
      await wallet.call(nft.address, nft2contract.methods.safeTransferFrom(wallet.address, accounts[0], 3).encodeABI())
    } catch (e) {
    }
    
  })

  it("should put wallet on lien", async () => {
      await wallet.safeTransferFrom(accounts[0], accounts[8], '45184769119825578793267361984150023626324968398689252800945352498587212057661')
  })

  it("should not withdraw assets on lien", async () => {
    try{
      await wallet.removeCollateral(nft.address, 3)
    } catch (e) {
    }
})
})