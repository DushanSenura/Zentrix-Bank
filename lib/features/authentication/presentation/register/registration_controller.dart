import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/providers.dart';
import '../../../../shared/models/models.dart';
import '../../domain/auth_repository.dart';
import '../../domain/identity_verification_service.dart';
import 'registration_fields.dart';

@immutable
class RegistrationState {
  const RegistrationState({
    required this.step,
    required this.values,
    this.documents = const {},
    this.capturing,
    this.submitting = false,
    this.created,
    this.forward = true,
  });
  final int step;
  final bool forward, submitting;
  final Map<String, String> values;
  final Set<KycDocument> documents;
  final KycDocument? capturing;
  final AppUser? created;

  bool get identityComplete => documents.length == KycDocument.values.length;

  RegistrationState copyWith({
    int? step,
    bool? forward,
    Map<String, String>? values,
    Set<KycDocument>? documents,
    KycDocument? capturing,
    bool clearCapturing = false,
    bool? submitting,
    AppUser? created,
  }) => RegistrationState(
    step: step ?? this.step,
    forward: forward ?? this.forward,
    values: values ?? this.values,
    documents: documents ?? this.documents,
    capturing: clearCapturing ? null : (capturing ?? this.capturing),
    submitting: submitting ?? this.submitting,
    created: created ?? this.created,
  );
}

/// Holds the in-progress application. Passwords are deliberately not stored here;
/// they live in the review step's text controller and are passed straight to [submit].
class RegistrationController extends Notifier<RegistrationState> {
  @override
  RegistrationState build() => const RegistrationState(
    step: 0,
    values: {
      'nationality': 'Sri Lankan',
      'country': 'Sri Lanka',
      'accountType': 'Savings',
    },
  );

  void setValue(String key, String value) => state = state.copyWith(values: {...state.values, key: value});

  void next() {
    if (state.step < registrationSteps.length - 1) state = state.copyWith(step: state.step + 1, forward: true);
  }

  void back() {
    if (state.step > 0) state = state.copyWith(step: state.step - 1, forward: false);
  }

  Future<void> capture(KycDocument document) async {
    if (state.capturing != null) return;
    state = state.copyWith(capturing: document);
    final ok = await ref.read(identityServiceProvider).capture(document);
    state = state.copyWith(
      documents: ok ? {...state.documents, document} : null,
      clearCapturing: true,
    );
  }

  /// Returns an error message, or null when the account was created.
  Future<String?> submit({required String username, required String password}) async {
    state = state.copyWith(submitting: true);
    try {
      final user = await ref.read(authRepositoryProvider).register(
        fullName: state.values['fullName']!.trim(),
        username: username,
        password: password,
        initialDeposit: double.parse(state.values['initialDeposit']!.replaceAll(',', '')),
        profile: state.values,
      );
      // Mock mode only: open the customer's books with what they deposited. A real backend does this itself.
      ref.read(mockBankProvider).openAccount(
        user,
        deposit: double.parse(state.values['initialDeposit']!.replaceAll(',', '')),
        type: state.values['accountType'] == 'Current' ? AccountType.current : AccountType.savings,
      );
      state = state.copyWith(created: user, submitting: false);
      return null;
    } on AuthException catch (e) {
      state = state.copyWith(submitting: false);
      return e.message;
    }
  }
}

final registrationProvider = NotifierProvider.autoDispose<RegistrationController, RegistrationState>(
  RegistrationController.new,
);
