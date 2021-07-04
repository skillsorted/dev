const BAMM = artifacts.require("BAMM");


async function deployBAMM() {
  //(address _priceAggregator, address payable _SP, address _LUSD, address _LQTY, uint _maxDiscount, address payable _feePool)
  const _priceAggregator = "0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419"
  const _SP = "0x66017D22b0f8556afDd19FC67041899Eb65a21bb"
  const _LUSD = "0x5f98805A4E8be255a32880FDeC7F6728C6568bA0"
  const _LQTY = "0x6DEA81C8171D0bA574754EF6F8b412F2Ed88c54D"
  const _maxDiscount = 4000
  const _feePool = "0x4D5d6611Ee4C1b67D79e684d3f0669cF48f46A0C"
  const bamm = await BAMM.new(_priceAggregator, _SP, _LUSD, _LQTY, _maxDiscount, _feePool)

  console.log(bamm.address)
}


async function swap() {
  const bamm = await BAMM.at("0xFEEF6A3cC16DC3f1fcd3dCcb6052F4539cF6f1EC")
  const designer = "0x4D5d6611Ee4C1b67D79e684d3f0669cF48f46A0C"
  await hre.network.provider.request({
    method: "hardhat_impersonateAccount",
    params: [designer]}
  );

  console.log("trying")

  await bamm.swap(1, designer, {from: designer})

  console.log("trying..")  
}

async function run() {
  //while(true) {
    //await sleep(10000)    
    //console.log("running again")
    //await approveScoreChangeAndTrasnferTokens()
    //return
    //await pumpNonce(80)
    //return
    //await approveScoreChangeAndTrasnferTokens()
    //return
    //await listTwoCoins()
    //await createAcountToExport()
    //return

    deployBAMM()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });
  //}  
}


run()
