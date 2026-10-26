import 'package:flutter_test/flutter_test.dart';
import 'package:falt/auth/company_gateway.dart';

void main() {
  const companyId = '11111111-1111-4111-8111-111111111111';

  test('lists memberships through the exact my_companies RPC', () async {
    String? functionName;
    Map<String, dynamic>? params;
    final gateway = CompanyGateway.forTesting(
      rpc: (name, {rpcParams}) async {
        functionName = name;
        params = rpcParams;
        return [
          {
            'id': companyId,
            'name': 'Trygga Tak AB',
            'trade_profile': 'Tak',
            'role': 'owner',
          },
        ];
      },
    );

    final companies = await gateway.listMyCompanies();

    expect(functionName, 'my_companies');
    expect(params, isNull);
    expect(companies.single.id, companyId);
    expect(companies.single.tradeProfile, 'Tak');
    expect(companies.single.role, 'owner');
  });

  test('creates a company with the exact RPC parameter names', () async {
    String? functionName;
    Map<String, dynamic>? params;
    final gateway = CompanyGateway.forTesting(
      rpc: (name, {rpcParams}) async {
        functionName = name;
        params = rpcParams;
        return {
          'id': companyId,
          'name': 'Måleri i Väster',
          'trade_profile': 'Måleri',
          'role': 'owner',
        };
      },
    );

    final company = await gateway.createCompany(
      name: 'Måleri i Väster',
      tradeProfile: 'Måleri',
    );

    expect(functionName, 'create_company');
    expect(params, {
      'p_name': 'Måleri i Väster',
      'p_trade_profile': 'Måleri',
    });
    expect(company.name, 'Måleri i Väster');
  });

  test('rejects malformed company RPC responses', () async {
    final gateway = CompanyGateway.forTesting(
      rpc: (_, {rpcParams}) async => [
        {'id': 'not-a-uuid', 'name': 'Trasigt'},
      ],
    );

    expect(gateway.listMyCompanies, throwsFormatException);
  });

  test('rejects a malformed create response instead of guessing', () async {
    final gateway = CompanyGateway.forTesting(
      rpc: (_, {rpcParams}) async => {'name': 'Saknar id'},
    );

    expect(
      () => gateway.createCompany(name: 'Saknar id', tradeProfile: 'Annat'),
      throwsFormatException,
    );
  });
}
