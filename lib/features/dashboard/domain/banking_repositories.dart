import '../../../shared/models/models.dart';
import '../../../shared/models/payment_models.dart';

abstract interface class AccountRepository {
  Future<List<BankAccount>> accounts();

  /// Opens a savings or current account, funded by moving [amount] out of [fromAccountId].
  /// Fixed deposits have their own repository. Throws `PaymentException` when the bank refuses.
  Future<BankAccount> open({required AccountType type, required String name, required String fromAccountId, required double amount});
}

abstract interface class CardRepository {
  Future<List<BankCard>> cards();

  /// Freezes or unfreezes a card. Throws if the bank could not apply the change.
  Future<void> setFrozen(String cardId, bool frozen);

  Future<CardControls> controls(String cardId);

  /// Throws [CardException] when the bank refuses (for example a limit above its maximum).
  Future<void> updateControls(String cardId, CardControls controls);

  /// Throws [CardException] when [currentPin] is wrong or [newPin] is not acceptable.
  /// The PINs are card PINs (4 digits) and are passed straight through, never stored.
  Future<void> changePin(String cardId, {required String currentPin, required String newPin});

  /// Permanently blocks the card and orders a replacement.
  Future<void> reportLostOrStolen(String cardId);

  /// Asks the bank for a new card linked to [accountId]. Neither kind is usable at once:
  ///  * a [CardKind.virtual] card waits for the bank to approve and activate it ([CardIssuance.pendingApproval]);
  ///  * a [CardKind.debit] card is made by the bank ([CardIssuance.preparing]) and becomes ready to collect from
  ///    [collectionBranch] after [debitCardPreparationDays] days ([CardIssuance.readyToCollect]).
  /// Throws [CardException] when the bank refuses.
  Future<BankCard> requestCard({required CardKind kind, required String accountId, required String holder, String? collectionBranch});

  /// Switches on a debit card the customer has collected from the branch. Virtual cards can't be activated here:
  /// the bank does that. Throws [CardException] if the card isn't ready or isn't the customer's to activate.
  Future<void> activateCard(String cardId);
}

abstract interface class TransactionRepository {
  /// Newest first.
  Future<List<Transaction>> transactions();

  /// The payment that produced [transactionId], if it was made in this app and can be repeated.
  Future<PaymentDraft?> repeatDraft(String transactionId);
}
