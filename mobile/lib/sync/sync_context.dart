class SyncContext {
  const SyncContext({
    required this.accountId,
    required this.companyId,
    required this.deviceId,
  });

  void validate() {
    requireStableUuid('accountId', accountId);
    requireStableUuid('companyId', companyId);
    requireStableUuid('deviceId', deviceId);
  }

  static final _uuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
  );

  static void requireStableUuid(String field, String value) {
    if (!_uuidPattern.hasMatch(value)) {
      throw ArgumentError.value(value, field, 'Must be a stable UUID string');
    }
  }

  final String accountId;
  final String companyId;
  final String deviceId;
}
