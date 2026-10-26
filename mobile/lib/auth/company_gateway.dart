import 'package:supabase_flutter/supabase_flutter.dart';

typedef CompanyRpc = Future<Object?> Function(
  String functionName, {
  Map<String, dynamic>? rpcParams,
});

class CompanySummary {
  const CompanySummary({
    required this.id,
    required this.name,
    required this.tradeProfile,
    required this.role,
  });

  final String id;
  final String name;
  final String tradeProfile;
  final String role;

  factory CompanySummary.fromJson(Map<String, dynamic> json) {
    final id = _requiredString(json, 'id');
    if (!_uuidPattern.hasMatch(id)) {
      throw FormatException('Company id is not a UUID.');
    }
    final name = _requiredString(json, 'name').trim();
    final tradeProfile = _requiredString(json, 'trade_profile').trim();
    final role = _requiredString(json, 'role').trim();
    if (name.isEmpty || tradeProfile.isEmpty || role.isEmpty) {
      throw const FormatException('Company response contained an empty field.');
    }
    return CompanySummary(
      id: id,
      name: name,
      tradeProfile: tradeProfile,
      role: role,
    );
  }

  static String _requiredString(Map<String, dynamic> json, String key) {
    final value = json[key];
    if (value is! String) throw FormatException('Company field $key is invalid.');
    return value;
  }
}

class CompanyGateway {
  factory CompanyGateway({required SupabaseClient client}) =>
      CompanyGateway._((name, {rpcParams}) async => client.rpc(
            name,
            params: rpcParams,
          ));

  CompanyGateway.forTesting({required CompanyRpc rpc}) : this._(rpc);

  CompanyGateway._(this._rpc);

  final CompanyRpc _rpc;

  Future<List<CompanySummary>> listMyCompanies() async {
    final response = await _rpc('my_companies');
    if (response is! List) {
      throw const FormatException('Company list response was not a list.');
    }
    return response.map(_parseMap).map(CompanySummary.fromJson).toList();
  }

  Future<CompanySummary> createCompany({
    required String name,
    required String tradeProfile,
  }) async {
    final response = await _rpc(
      'create_company',
      rpcParams: {
        'p_name': name.trim(),
        'p_trade_profile': tradeProfile,
      },
    );
    if (response is! Map) {
      throw const FormatException('Create company response was not an object.');
    }
    return CompanySummary.fromJson(_parseMap(response));
  }

  static Map<String, dynamic> _parseMap(Object? value) {
    if (value is! Map) throw const FormatException('Company row was not an object.');
    try {
      return Map<String, dynamic>.from(value);
    } on TypeError {
      throw const FormatException('Company row had invalid fields.');
    }
  }
}

final _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
);
