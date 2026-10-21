import "package:dio/dio.dart";
import "package:driver_pilot/shipper/erp_integrations.dart";
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
                    {
                      "id": "whd_2",
                      "eventId": "evt_retry",
                      "status": "PENDING",
                      "attempts": 3,
                      "lastHttpStatus": 500,
                    },
                  ],
                },
              ),
            );
            return;
          }
          handler.reject(
            DioException(
                requestOptions: options, message: "unexpected ${options.path}"),
          );
        },
      ),
    );
  });

  tearDown(() {
    CustomerSession.skipRefreshInTests = false;
    CustomerSession.clear();
  });

  testWidgets("CustomerIntegrationsScreen shows admin ERP integrations UI",
      (tester) async {
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
        theme: DriverTheme.theme(),
        home: const CustomerIntegrationsScreen(),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.text("Integrations"), findsOneWidget);
    expect(find.text("ERP Smoke Co"), findsAtLeastNWidgets(1));
    expect(find.text("Create key"), findsOneWidget);
    expect(find.text("Save settings"), findsOneWidget);
    expect(find.text("Send a test webhook"), findsOneWidget);
    expect(find.text("Recent webhook calls"), findsOneWidget);
    expect(find.text("abc123"), findsOneWidget);
    expect(find.text("evt_test"), findsOneWidget);
  });

  for (final textScale in [1.0, 2.0]) {
    testWidgets(
        "CustomerIntegrationsScreen fits 360 x 800 at ${(textScale * 100).round()}% text",
        (tester) async {
      CustomerSession.applyForTest(
        userFullName: "ERP Admin",
        userPhone: "9111009900",
        customerOrgId: "org_test",
        customerOrgName: "ERP Smoke Co",
        customerRole: "CUSTOMER_ADMIN",
      );

      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: DriverTheme.theme(),
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!),
          home: const CustomerIntegrationsScreen(),
        ),
      );
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(tester.takeException(), isNull,
          reason: "nothing overflows at the top of the screen");

      // The list builds lazily, so scroll to the end to lay out every field.
      final list = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(find.text("Retry"), 200,
          scrollable: list);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull,
          reason: "nothing overflows further down the screen");

      await tester.scrollUntilVisible(find.text("Payment policy"), -200,
          scrollable: list);
      await tester.pumpAndSettle();
      final chosenPolicy = tester.widget<Text>(
          find.text("Portal checkout (Razorpay in customer web)"));
      expect(chosenPolicy.maxLines, 1,
          reason: "the closed field keeps the chosen policy to one line");
      expect(chosenPolicy.overflow, TextOverflow.ellipsis);

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull,
          reason: "the payment policy choices fit the open menu");
      expect(find.text("ERP pre-authorized (book without portal checkout)"),
          findsOneWidget,
          reason: "the menu is open and shows the other choice");
    });
  }

  testWidgets("CustomerIntegrationsScreen shows admin required for non-admin",
      (tester) async {
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

    expect(find.textContaining("Only company admins"), findsOneWidget);
    expect(find.text("Create key"), findsNothing);
  });
}
