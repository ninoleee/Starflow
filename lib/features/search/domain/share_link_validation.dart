enum ShareLinkValidationStatus {
  valid,
  invalid,
  unavailable,
}

class ShareLinkValidationResult {
  const ShareLinkValidationResult.valid()
      : status = ShareLinkValidationStatus.valid,
        reason = '';

  const ShareLinkValidationResult.invalid(this.reason)
      : status = ShareLinkValidationStatus.invalid;

  const ShareLinkValidationResult.unavailable(this.reason)
      : status = ShareLinkValidationStatus.unavailable;

  final ShareLinkValidationStatus status;
  final String reason;

  bool get isValid => status == ShareLinkValidationStatus.valid;

  bool get isInvalid => status == ShareLinkValidationStatus.invalid;
}
