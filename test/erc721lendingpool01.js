const Lending = artifacts.require("ERC721LendingPoolETH01")
const ERC721 = artifacts.require("Doodles")
const BN = require('bn.js')

contract("ERC721 Lending", async accounts => {
    /*
    9123ad2f6b0668bf0eb604be9d5751c0a91b8ca38dd2959c3eda8f510516a9de: lender
    accounts[1]: borrower

    */
  before(async () => {
    // punk = await Punk.new()
    // TODO: spawn ERC721 insatance
    nft = await ERC721.new()
    nft2 = await ERC721.new()
    await nft.setSaleState(true)
    lender_pkey = "9123ad2f6b0668bf0eb604be9d5751c0a91b8ca38dd2959c3eda8f510516a9de"
    lender_address = "0xf31EEB5433cE3F307d20D07Ac0329Da857eEb485"
    lending = await Lending.new()
    await lending.initialize(nft.address)
    await lending.setDurationParam(10, [1000, 3000])
    await lending.setValuationSigner(lender_address)
    web3.eth.sendTransaction({from: accounts[2],to: lending.address, value: web3.utils.toWei("1", "ether")})
    /*
        address nft,
        uint punkID,
        uint valuation,
        uint maxLTVBPS,
        uint liquidationLTVBPS,
        uint loanDuration,
        uint expireAtBlock,
        uint interest1000000XBPSBlock,
    */
    lending_params = [1,  100000000000, 20]
    valuation_hash = await lending.getMessageHash(nft.address, ...lending_params)
    signed_valuation_hash = await web3.eth.accounts.sign(valuation_hash, lender_pkey)
  });

  it("should verify a correct signature", async () => {
    assert.equal(true, await lending.verify(nft.address, ...lending_params, lender_address, signed_valuation_hash.signature))
  })

  it("should approve the contract for spending NFTs", async () => {
    //await lending.registerProxy({from: accounts[1]});
    await nft.setApprovalForAll(lending.address, true, {from: accounts[1]})
  })

  it("should mint NFTs", async () => {
    await nft.mint(5, {from: accounts[1], value: 1000000000000000000})
    await nft.safeTransferFrom(accounts[1], lending.address, 4,{from: accounts[1]})
  })
  it("should not borrow more than what it could", async () => {
    try{
      await lending.borrowETH(lending_params[1], lending_params[0], 10, lending_params[2], 30000000001, signed_valuation_hash.signature, {from: accounts[1]})
    } catch (e) {
      assert(e)
    }
    
  })

  it("should not supply fake valuation", async () => {
    try{
      await lending.borrowETH(8988888888888888, lending_params[0], 10, lending_params[2], 8988888888888888, signed_valuation_hash.signature, {from: accounts[1]})
    } catch (e) {
      assert(e)
    }
    
  })
  it("should borrow some money and the NFT is located in the contract", async () => {
    const prev_balance = await web3.eth.getBalance(accounts[1])
    const receipt = await lending.borrowETH(lending_params[1], lending_params[0], 10, lending_params[2], 30000000000, signed_valuation_hash.signature, {from: accounts[1]})
    web3.eth.sendTransaction({from: accounts[2],to: lending.address, value: web3.utils.toWei("1", "ether")})
    web3.eth.sendTransaction({from: accounts[2],to: lending.address, value: web3.utils.toWei("1", "ether")})
    const gasUsed = receipt.receipt.gasUsed;
    //assert.equal(new BN((await web3.eth.getBalance(accounts[1]))).add(new BN(gasUsed)).sub(new BN(prev_balance)) , new BN(30000000000))
    //console.log((await web3.eth.getBalance(accounts[1])).toString())
    //console.log(prev_balance.toString())
    assert.equal(lending.address, await nft.ownerOf(1))
  })

  it("should return part of the money (eating into principal)", async () => {
    await lending.repayETH(1, {from: accounts[1], value: 10000009000})
    assert.equal(lending.address, await nft.ownerOf(1))
    assert.equal(20000000000, await lending.outstanding(1))
  })

  it("should return part of the money (doesn't eat into principal)", async () => {
    await lending.repayETH(1, {from: accounts[1], value: 100})
    assert.equal(lending.address, await nft.ownerOf(1))
    assert.equal(20000001900, await lending.outstanding(1))
  })

  it("admin should withdraw nfts", async () => {
    await lending.withdrawERC721(nft.address, 4)
  })

  it("admin should not withdraw nfts on lien", async () => {
    try{
      await lending.withdrawERC721(nft.address, 1)
    }catch(e) {
      assert(e)
    }
    
  })
  it("should not let people steal NFTs", async () => {
    try{
      await nft.safeTransferFrom(lending.address, accounts[5], 1)
    } catch (e) {
      assert (e)
    }
  })

  it("should return all of the money", async () => {
    await lending.repayETH(1, {from: accounts[3], value: (await lending.outstanding(1))+1001})
    assert.equal(accounts[1], await nft.ownerOf(1))
  })



  it("admin should withdraw proceeds", async () => {
    const prev_balance = await web3.eth.getBalance(lending.address)
    console.log((await web3.eth.getBalance(accounts[0])).toString())
    await lending.withdraw(prev_balance)
    console.log((await web3.eth.getBalance(accounts[0])).toString())
  })

  
  
});

contract("ERC721 Lending liquidate case", async accounts => {
  /*
  9123ad2f6b0668bf0eb604be9d5751c0a91b8ca38dd2959c3eda8f510516a9de: lender
  accounts[1]: borrower

  */
before(async () => {
  // punk = await Punk.new()
  // TODO: spawn ERC721 insatance
  nft = await ERC721.new()
  nft2 = await ERC721.new()
  await nft.setSaleState(true)
  lender_pkey = "9123ad2f6b0668bf0eb604be9d5751c0a91b8ca38dd2959c3eda8f510516a9de"
  lender_address = "0xf31EEB5433cE3F307d20D07Ac0329Da857eEb485"
  lending = await Lending.new()
  await lending.initialize(nft.address)
  await lending.setDurationParam(1, [1000, 3000])
  await lending.setValuationSigner(lender_address)
  web3.eth.sendTransaction({from: accounts[2],to: lending.address, value: web3.utils.toWei("1", "ether")})
  /*
      address nft,
      uint punkID,
      uint valuation,
      uint maxLTVBPS,
      uint liquidationLTVBPS,
      uint loanDuration,
      uint expireAtBlock,
      uint interest1000000XBPSBlock,
  */
  lending_params = [1,  100000000000, 20]
  valuation_hash = await lending.getMessageHash(nft.address, ...lending_params)
  signed_valuation_hash = await web3.eth.accounts.sign(valuation_hash, lender_pkey)
});


it("should approve the contract for spending NFTs", async () => {
  //await lending.registerProxy({from: accounts[1]});
  await nft.setApprovalForAll(lending.address, true, {from: accounts[1]})
})

it("should mint NFTs", async () => {
  await nft.mint(5, {from: accounts[1], value: 1000000000000000000})
  await nft.safeTransferFrom(accounts[1], lending.address, 4,{from: accounts[1]})
})
it("should not borrow more than what it could", async () => {
  try{
    await lending.borrowETH(lending_params[1], lending_params[0], 1, lending_params[2], 30000000001, signed_valuation_hash.signature, {from: accounts[1]})
  } catch (e) {
    assert(e)
  }
  
})
it("should borrow some money and the NFT is located in the contract", async () => {
  const prev_balance = await web3.eth.getBalance(accounts[1])
  const receipt = await lending.borrowETH(lending_params[1], lending_params[0], 1, lending_params[2], 30000000000, signed_valuation_hash.signature, {from: accounts[1]})
  
  const gasUsed = receipt.receipt.gasUsed;
  //assert.equal(new BN((await web3.eth.getBalance(accounts[1]))).add(new BN(gasUsed)).sub(new BN(prev_balance)) , new BN(30000000000))
  //console.log((await web3.eth.getBalance(accounts[1])).toString())
  //console.log(prev_balance.toString())
  assert.equal(lending.address, await nft.ownerOf(1))
})

it("should not be liquidated when not expired", async () => {
  try{
    await lending.liquidateLoan(1)
  } catch(e) {
    assert(e)
  }
  
  
  assert.equal(lending.address, await nft.ownerOf(1))
  web3.eth.sendTransaction({from: accounts[2],to: lending.address, value: web3.utils.toWei("1", "ether")})
  //web3.eth.sendTransaction({from: accounts[2],to: lending.address, value: web3.utils.toWei("1", "ether")})
  
})
function delay(t, val) {
  return new Promise(function(resolve) {
      setTimeout(function() {
          resolve(val);
      }, t);
  });
}

it("should be liquidated when expired", async () => {
  await delay(2000)
  await lending.liquidateLoan(1)
  assert.equal(accounts[0], await nft.ownerOf(1))
})


});

contract("ERC721 Lending zero interest", async accounts => {
  /*
  9123ad2f6b0668bf0eb604be9d5751c0a91b8ca38dd2959c3eda8f510516a9de: lender
  accounts[1]: borrower

  */
before(async () => {
  // punk = await Punk.new()
  // TODO: spawn ERC721 insatance
  nft = await ERC721.new()
  nft2 = await ERC721.new()
  await nft.setSaleState(true)
  lender_pkey = "9123ad2f6b0668bf0eb604be9d5751c0a91b8ca38dd2959c3eda8f510516a9de"
  lender_address = "0xf31EEB5433cE3F307d20D07Ac0329Da857eEb485"
  lending = await Lending.new()
  await lending.initialize(nft.address)
  await lending.setDurationParam(10, [0, 3000])
  await lending.setValuationSigner(lender_address)
  web3.eth.sendTransaction({from: accounts[2],to: lending.address, value: web3.utils.toWei("1", "ether")})
  /*
      address nft,
      uint punkID,
      uint valuation,
      uint maxLTVBPS,
      uint liquidationLTVBPS,
      uint loanDuration,
      uint expireAtBlock,
      uint interest1000000XBPSBlock,
  */
  lending_params = [1,  100000000000, 20]
  valuation_hash = await lending.getMessageHash(nft.address, ...lending_params)
  signed_valuation_hash = await web3.eth.accounts.sign(valuation_hash, lender_pkey)
});

it("should approve the contract for spending NFTs", async () => {
  //await lending.registerProxy({from: accounts[1]});
  await nft.setApprovalForAll(lending.address, true, {from: accounts[1]})
})

it("should mint NFTs", async () => {
  await nft.mint(5, {from: accounts[1], value: 1000000000000000000})
  await nft.safeTransferFrom(accounts[1], lending.address, 4,{from: accounts[1]})
})
it("should not borrow more than what it could", async () => {
  try{
    await lending.borrowETH(lending_params[1], lending_params[0], 10, lending_params[2], 30000000001, signed_valuation_hash.signature, {from: accounts[1]})
  } catch (e) {
    assert(e)
  }
  
})
it("should borrow some money and the NFT is located in the contract", async () => {
  const prev_balance = await web3.eth.getBalance(accounts[1])
  const receipt = await lending.borrowETH(lending_params[1], lending_params[0], 10, lending_params[2], 30000000000, signed_valuation_hash.signature, {from: accounts[1]})
  web3.eth.sendTransaction({from: accounts[2],to: lending.address, value: web3.utils.toWei("1", "ether")})
  web3.eth.sendTransaction({from: accounts[2],to: lending.address, value: web3.utils.toWei("1", "ether")})
  const gasUsed = receipt.receipt.gasUsed;
  //assert.equal(new BN((await web3.eth.getBalance(accounts[1]))).add(new BN(gasUsed)).sub(new BN(prev_balance)) , new BN(30000000000))
  //console.log((await web3.eth.getBalance(accounts[1])).toString())
  //console.log(prev_balance.toString())
  assert.equal(lending.address, await nft.ownerOf(1))
})

it("should return part of the money (eating into principal)", async () => {
  await lending.repayETH(1, {from: accounts[1], value: 10000000000})
  assert.equal(lending.address, await nft.ownerOf(1))
  assert.equal(20000000000, await lending.outstanding(1))
})



it("should return all of the money", async () => {
  await lending.repayETH(1, {from: accounts[3], value: (await lending.outstanding(1))})
  assert.equal(accounts[1], await nft.ownerOf(1))
})


});