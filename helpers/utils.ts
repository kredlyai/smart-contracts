import BigNumber from "bignumber.js";

BigNumber.config({
  FORMAT: {
    decimalSeparator: ".",
    groupSize: 0,
    groupSeparator: "",
    secondaryGroupSize: 0,
    fractionGroupSeparator: "",
    fractionGroupSize: 0,
  },
  ROUNDING_MODE: BigNumber.ROUND_DOWN,
  EXPONENTIAL_AT: 1e9,
})

const convertToUnit = (amount: string | number, decimals: number) => {
  return new BigNumber(amount).times(new BigNumber(10).pow(decimals)).toString();
}

const scaleDownBy = (amount: string | number, decimals: number) => {
  return new BigNumber(amount).dividedBy(new BigNumber(10).pow(decimals)).toString();
}

const AddressOne = "0x0000000000000000000000000000000000000001";

export {
  convertToUnit,
  scaleDownBy,
  AddressOne,
}
