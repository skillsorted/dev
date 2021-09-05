const deploymentHelper = require("./../../utils/deploymentHelpers.js")
const testHelpers = require("./../../utils/testHelpers.js")
const th = testHelpers.TestHelper
const dec = th.dec
const toBN = th.toBN
const mv = testHelpers.MoneyValues
const timeValues = testHelpers.TimeValues

const TroveManagerTester = artifacts.require("TroveManagerTester")
const LUSDToken = artifacts.require("LUSDToken")
const NonPayable = artifacts.require('NonPayable.sol')
const BAMM = artifacts.require("BAMM.sol")
const BLens = artifacts.require("BLens.sol")
const ChainlinkTestnet = artifacts.require("ChainlinkTestnet.sol")
const BSPToken = artifacts.require("BSPToken.sol")
const CToken = artifacts.require("MockCToken.sol")

const ZERO = toBN('0')
const ZERO_ADDRESS = th.ZERO_ADDRESS
const maxBytes32 = th.maxBytes32

const getFrontEndTag = async (stabilityPool, depositor) => {
  return (await stabilityPool.deposits(depositor))[1]
}

contract('BAMM', async accounts => {
  const [owner,
    defaulter_1, defaulter_2, defaulter_3,
    whale,
    alice, bob, carol, dennis, erin, flyn,
    A, B, C, D, E, F,
    u1, u2, u3, u4, u5,
    v1, v2, v3, v4, v5,
    frontEnd_1, frontEnd_2, frontEnd_3,
    bammOwner
  ] = accounts;

  const [bountyAddress, lpRewardsAddress, multisig] = accounts.slice(997, 1000)

  const frontEnds = [frontEnd_1, frontEnd_2, frontEnd_3]
  let contracts
  let priceFeed
  let lusdToken
  let sortedTroves
  let troveManager
  let activePool
  let stabilityPool
  let bamm
  let lens
  let chainlink
  let defaultPool
  let borrowerOperations
  let lqtyToken
  let communityIssuance
  let bspToken
  let cToken

  let gasPriceInWei

  const feePool = "0x1000000000000000000000000000000000000001"

  const getOpenTroveLUSDAmount = async (totalDebt) => th.getOpenTroveLUSDAmount(contracts, totalDebt)
  const openTrove = async (params) => th.openTrove(contracts, params)
  //const assertRevert = th.assertRevert

  describe("BAMM", async () => {

    before(async () => {
      gasPriceInWei = await web3.eth.getGasPrice()
    })

    beforeEach(async () => {
      contracts = await deploymentHelper.deployLiquityCore()
      contracts.troveManager = await TroveManagerTester.new()
      contracts.lusdToken = await LUSDToken.new(
        contracts.troveManager.address,
        contracts.stabilityPool.address,
        contracts.borrowerOperations.address
      )
      const LQTYContracts = await deploymentHelper.deployLQTYContracts(bountyAddress, lpRewardsAddress, multisig)

      priceFeed = contracts.priceFeedTestnet
      lusdToken = contracts.lusdToken
      sortedTroves = contracts.sortedTroves
      troveManager = contracts.troveManager
      activePool = contracts.activePool
      stabilityPool = contracts.stabilityPool
      defaultPool = contracts.defaultPool
      borrowerOperations = contracts.borrowerOperations
      hintHelpers = contracts.hintHelpers

      lqtyToken = LQTYContracts.lqtyToken
      communityIssuance = LQTYContracts.communityIssuance

      await deploymentHelper.connectLQTYContracts(LQTYContracts)
      await deploymentHelper.connectCoreContracts(contracts, LQTYContracts)
      await deploymentHelper.connectLQTYContractsToCore(LQTYContracts, contracts)

      // Register 3 front ends
      //await th.registerFrontEnds(frontEnds, stabilityPool)

      // deploy BAMM
      chainlink = await ChainlinkTestnet.new(priceFeed.address)

      const kickbackRate_F1 = toBN(dec(5, 17)) // F1 kicks 50% back to depositor
      await stabilityPool.registerFrontEnd(kickbackRate_F1, { from: frontEnd_1 })

      bamm = await BAMM.new(chainlink.address, stabilityPool.address, lusdToken.address, lqtyToken.address, 400, feePool, frontEnd_1, {from: bammOwner})
      lens = await BLens.new()

      cToken = await CToken.new()
      bspToken = await BSPToken.new(lusdToken.address, lqtyToken.address, bamm.address, cToken.address)
    })

    it("mint(): mint first token", async () => {
      // --- SETUP --- Give Alice a least 200
      await openTrove({ extraLUSDAmount: toBN(200), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })

      // --- TEST ---
      await lusdToken.approve(bspToken.address, toBN(200), { from: alice })
      await bspToken.mint(toBN(200), { from: alice })

      assert.equal((await bspToken.balanceOf(alice)).toString(), toBN(dec(1, 18)).toString())
    })

    it("burn(): burn half the tokens", async () => {
      await web3.eth.sendTransaction({from: whale, to: bamm.address, value: toBN(dec(1, 18))})
      // --- SETUP --- Give Alice a least 200
      await openTrove({ extraLUSDAmount: toBN(200), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })

      await lusdToken.approve(bspToken.address, toBN(200), { from: alice })
      await bspToken.mint(toBN(200), { from: alice })

      assert.equal((await bspToken.balanceOf(alice)).toString(), toBN(dec(1, 18)).toString())

      const lusdBefore = await lusdToken.balanceOf(alice)
      const ethBefore = await toBN(await web3.eth.getBalance(alice))
      await bspToken.burn(toBN(dec(5, 17)), { from: alice, gasPrice: 0 })
      const lusdAfter = await lusdToken.balanceOf(alice)
      const ethAfter = await toBN(await web3.eth.getBalance(alice))      

      assert.equal((lusdAfter.sub(lusdBefore)).toString(), toBN(100).toString())
      assert.equal((ethAfter.sub(ethBefore)).toString(), toBN(dec(5,17)).toString())      
    })

    it("harvestLqty(): send tokens to ctoken and harvest lqty", async () => {
      await openTrove({ extraLUSDAmount: toBN(dec(10000, 18)), ICR: toBN(dec(10, 18)), extraParams: { from: whale } })

      // A, B, C, open troves 
      await openTrove({ extraLUSDAmount: toBN(dec(1000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: A } })
      await openTrove({ extraLUSDAmount: toBN(dec(2000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: B } })
      await openTrove({ extraLUSDAmount: toBN(dec(3000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: C } })
      await openTrove({ extraLUSDAmount: toBN(dec(1000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: D } })
      await openTrove({ extraLUSDAmount: toBN(dec(2000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: E } })
      await openTrove({ extraLUSDAmount: toBN(dec(3000, 18)), ICR: toBN(dec(2, 18)), extraParams: { from: F } })
      
      // D, E provide to bamm, F provide to SP
      await lusdToken.approve(bspToken.address, dec(1000, 18), { from: D })
      await lusdToken.approve(bspToken.address, dec(2000, 18), { from: E })
      await bspToken.mint(dec(1000, 18), { from: D })
      await bspToken.mint(dec(2000, 18), { from: E })
      await stabilityPool.provideToSP(dec(3000, 18), frontEnd_1, { from: F })

      await bspToken.transfer(cToken.address, await bspToken.balanceOf(D), {from: D})
      await bspToken.transfer(cToken.address, await bspToken.balanceOf(E), {from: E})      

      // Get F1, F2, F3 LQTY balances before, and confirm they're zero
      const D_LQTYBalance_Before = await lqtyToken.balanceOf(D)
      const E_LQTYBalance_Before = await lqtyToken.balanceOf(E)
      const F_LQTYBalance_Before = await lqtyToken.balanceOf(F)

      assert.equal(D_LQTYBalance_Before, '0')
      assert.equal(E_LQTYBalance_Before, '0')
      assert.equal(F_LQTYBalance_Before, '0')

      await th.fastForwardTime(timeValues.SECONDS_IN_ONE_HOUR, web3.currentProvider)

      await stabilityPool.withdrawFromSP(0, { from: F })
      await bspToken.harvestLqty({ from: D })
      await bspToken.harvestLqty({ from: E })      

      // Get F1, F2, F3 LQTY balances after, and confirm they have increased
      const D_LQTYBalance_After = await lqtyToken.balanceOf(D)
      const E_LQTYBalance_After = await lqtyToken.balanceOf(E)
      const F_LQTYBalance_After = await lqtyToken.balanceOf(F)

      assert((await lqtyToken.balanceOf(frontEnd_1)).gt(toBN(0)))
      assert.equal(D_LQTYBalance_After.add(D_LQTYBalance_After).toString(), E_LQTYBalance_After.toString())
      assert.equal(D_LQTYBalance_After.add(E_LQTYBalance_After).toString(), F_LQTYBalance_After.toString())
    })    

    it("liquidate(): liquidate half the tokens", async () => {
      await web3.eth.sendTransaction({from: whale, to: bamm.address, value: toBN(dec(1, 18))})
      // --- SETUP --- Give Alice a least 200
      await openTrove({ extraLUSDAmount: toBN(200), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })

      await lusdToken.approve(bspToken.address, toBN(200), { from: alice })
      await bspToken.mint(toBN(200), { from: alice })

      assert.equal((await bspToken.balanceOf(alice)).toString(), toBN(dec(1, 18)).toString())

      await bspToken.transfer(cToken.address, toBN(dec(1,18)), {from: alice})

      // simulate liquidation
      await cToken.setUnderlyingBalance(alice, toBN(dec(5,17)))
      await cToken.transfer(bspToken.address, carol, toBN(dec(5,17)))

      // liquidate
      const lusdBefore = await lusdToken.balanceOf(carol)
      const ethBefore = await toBN(await web3.eth.getBalance(carol))
      await bspToken.liquidate(alice, toBN(dec(5, 17)), { from: carol, gasPrice: 0 })
      const lusdAfter = await lusdToken.balanceOf(carol)
      const ethAfter = await toBN(await web3.eth.getBalance(carol))      

      assert.equal((lusdAfter.sub(lusdBefore)).toString(), toBN(100).toString())
      assert.equal((ethAfter.sub(ethBefore)).toString(), toBN(dec(5,17)).toString())
      assert.equal((await bspToken.balanceOf(carol)).toString(), "0")

      const avatarAddress = await bspToken.avatars(alice)
      const shareAmount = await bamm.balanceOf(avatarAddress)
      assert.equal(shareAmount.toString(), toBN(dec(5,17)).toString())
    })

    it("transfer(): check expected ctoken balance", async () => {
      // --- SETUP --- Give Alice a least 200
      await openTrove({ extraLUSDAmount: toBN(200), ICR: toBN(dec(2, 18)), extraParams: { from: alice } })

      await lusdToken.approve(bspToken.address, toBN(200), { from: alice })
      await bspToken.mint(toBN(200), { from: alice })

      assert.equal((await bspToken.balanceOf(alice)).toString(), toBN(dec(1, 18)).toString())

      await bspToken.transfer(cToken.address, toBN(dec(1,18)), {from: alice})
      const cbal1 = await bspToken.expectedCTokenBalance(alice)
      assert.equal(cbal1.toString(), toBN(dec(1,18)).toString())
      // simulate withdraw
      await cToken.transfer(bspToken.address, alice, toBN(dec(5,17)))
      const cbal2 = await bspToken.expectedCTokenBalance(alice)
      assert.equal(cbal2.toString(), toBN(dec(5,17)).toString())
    })    

  })
})


function almostTheSame(n1, n2) {
  n1 = Number(web3.utils.fromWei(n1))
  n2 = Number(web3.utils.fromWei(n2))
  //console.log(n1,n2)

  if(n1 * 1000 > n2 * 1001) return false
  if(n2 * 1000 > n1 * 1001) return false  
  return true
}

function in100WeiRadius(n1, n2) {
  const x = toBN(n1)
  const y = toBN(n2)

  if(x.add(toBN(100)).lt(y)) return false
  if(y.add(toBN(100)).lt(x)) return false  
 
  return true
}

async function assertRevert(txPromise, message = undefined) {
  try {
    const tx = await txPromise
    // console.log("tx succeeded")
    assert.isFalse(tx.receipt.status) // when this assert fails, the expected revert didn't occur, i.e. the tx succeeded
  } catch (err) {
    // console.log("tx failed")
    assert.include(err.message, "revert")
    
    if (message) {
       assert.include(err.message, message)
    }
  }
}