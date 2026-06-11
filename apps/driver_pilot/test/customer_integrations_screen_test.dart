import "package:dio/dio.dart";
import "package:driver_pilot/customer_flow.dart";
import "package:driver_pilot/customer_session.dart";
import "package:driver_pilot/driver_theme.dart";
import "package:driver_pilot/pilot_api.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  setUp(() {
    CustomerSession.clear();
    CustomerSession.skipRefreshInTests = true;
    api = Api("http://test");
    api.dio.interceptors.clear();
    api.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.path.contains("/v1/pilot/customer/integrations")) {
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                data: {
                  "connection": {
                    "id": "conn_test",
                    "displayName": "ERP Smoke Co",
                    "webhookUrl": "https://erp.example.com/hook",
                    "paymentPolicy": "portal_checkout",
                    "hasWebhookSecret": true,
                  },
                  "apiKeys": [
                    {
                      "keyId": "abc123",
                      "scopes": ["loads:read", "loads:write"],
                    },
                  ],
                  "recentDeliveries": [
                    {
                      "id": "whd_1",
                      "eventId": "evt_test",
                      "status": "DELIVERED",
                      "attempts": 1,
                      "lastHttpStatus": 200,
                    },
                  ],
                },
              ),
            );
            return;
          }
          handler.reject(
            DioException(requestOptions: options, message: "unexpected ${options.path}"),
          );
        },
      ),
    );
  });

  tearDown(() {
    CustomerSession.skipRefreshInTests = false;
    CustomerSession.clear();
  });

  testWidgets("CustomerIntegrationsScreen shows admin ERP integrations UI", (tester) async {
    CustomerSession.applyForTest(
      userFullName: "ERP Admin",
      userPhone: "9111009900",
      customerOrgId: "org_test",
      customerOrgName: "ERP Smoke Co",
      customerRole: "CUSTOMER_ADMIN",
    );

    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: DriverTheme.navy)),
        home: const CustomerIntegrationsScreen(),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.text("Integrations"), findsOneWidget);
    expect(find.text("ERP Smoke Co"), findsOneWidget);
    expect(find.text("Create key"), findsOneWidget);
    expect(find.text("Save settings"), findsOneWidget);
    expect(find.text("Send test ping"), findsOneWidget);
    expect(find.text("Recent webhook deliveries"), findsOneWidget);
    expect(find.text("abc123"), findsOneWidget);
    expect(find.text("evt_test"), findsOneWidget);
  });

  testWidgets("CustomerIntegrationsScreen shows admin required for non-admin", (tester) async {
    CustomerSession.applyForTest(
      userPhone: "9111009901",
      customerOrgId: "org_test",
      customerOrgName: "ERP Smoke Co",
      customerRole: "CUSTOMER_MEMBER",
    );

    await tester.pumpWidget(
      MaterialApp(
        home: const CustomerIntegrationsScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining("Only org admins"), findsOneWidget);
    expect(find.text("Create key"), findsNothing);
  });
}
