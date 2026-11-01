const ownBank = 'Zentrix Bank';

const banks = [
  ownBank,
  'Bank of Ceylon',
  'People’s Bank',
  'Commercial Bank',
  'Sampath Bank',
  'Hatton National Bank',
  'Nations Trust Bank',
  'Seylan Bank',
];

/// Flat fee for sending to another bank.
const interbankFee = 25.0;

double transferFeeFor(String bank) => bank == ownBank ? 0 : interbankFee;
