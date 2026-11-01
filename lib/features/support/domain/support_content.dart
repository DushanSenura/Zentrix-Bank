class Faq {
  const Faq(this.question, this.answer);
  final String question, answer;
}

const faqs = [
  Faq('How do I freeze my card?', 'Open the Cards tab, swipe to the card and switch on “Freeze card”. Switch it off to use the card again. Freezing is instant.'),
  Faq('What are my transfer limits?', 'You can set your own daily transfer limit under Security center → Transaction limits, up to the bank’s maximum of LKR 500,000 a day.'),
  Faq('Why was my transfer declined?', 'The most common reasons are insufficient funds, a recipient account we couldn’t verify, or reaching your daily limit. The message on the failed screen says which.'),
  Faq('How do I change my PIN or password?', 'Go to Profile → Security center. Changing either asks you to confirm the current one first.'),
  Faq('Are there fees?', 'Transfers to Zentrix accounts and your own accounts are free. Transfers to other banks cost LKR 25. The fee is always shown before you confirm.'),
  Faq('How do I report a lost card?', 'Freeze the card straight away from the Cards tab, then call us using the number in Help & support so we can replace it.'),
];

const supportPhone = '+94112345678';
const supportEmail = 'support@zentrixbank.example';

/// Rule-based replies for the prototype chat. Not a language model and not a person.
String botReply(String message) {
  final m = message.toLowerCase();
  bool has(List<String> words) => words.any(m.contains);
  if (has(['lost', 'stolen', 'fraud', 'unauthor', 'hack'])) {
    return 'I’m sorry to hear that. Please freeze your card from the Cards tab right now, then call us on $supportPhone so a person can help secure your account.';
  }
  if (has(['freeze', 'block card'])) {
    return 'To freeze a card, open the Cards tab and switch on “Freeze card”. It takes effect immediately.';
  }
  if (has(['limit'])) {
    return 'You can lower your daily transfer limit in Security center → Transaction limits. The bank’s maximum is LKR 500,000 a day.';
  }
  if (has(['fee', 'charge', 'cost'])) {
    return 'Own-account and Zentrix transfers are free; other banks cost LKR 25. You always see the fee before you confirm.';
  }
  if (has(['password'])) {
    return 'You can change your password under Profile → Security center → Change password.';
  }
  if (has(['pin'])) {
    return 'Change your PIN under Profile → Security center → Change PIN. You’ll confirm your current PIN first.';
  }
  if (has(['branch', 'atm', 'nearest'])) {
    return 'Open Help & support → Branches & ATMs to see locations near you.';
  }
  if (has(['hello', 'hi ', 'hey']) || m.trim() == 'hi') {
    return 'Hello! I’m the automated assistant. Ask me about cards, transfers, limits or fees.';
  }
  return 'I’m an automated assistant with a small set of answers, and I didn’t understand that. Try asking about cards, limits, fees or passwords — or call $supportPhone to reach a person.';
}
