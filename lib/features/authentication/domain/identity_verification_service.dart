enum KycDocument { idFront, selfie, addressProof }

/// Seam for a real KYC provider (document capture, liveness, address checks).
abstract interface class IdentityVerificationService {
  /// Resolves true when [document] was captured and accepted.
  Future<bool> capture(KycDocument document);
}

/// Simulated provider: it captures nothing and verifies nothing.
class MockIdentityVerificationService implements IdentityVerificationService {
  const MockIdentityVerificationService([this.delay = const Duration(milliseconds: 700)]);
  final Duration delay;

  @override
  Future<bool> capture(KycDocument document) async {
    await Future<void>.delayed(delay);
    return true;
  }
}
