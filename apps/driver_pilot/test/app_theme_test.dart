import 'package:driver_pilot/authorization_session.dart';
import 'package:driver_pilot/main.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:driver_pilot/ui/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/mock_api.dart';

void main() {
  testWidgets('The app stays light on a dark phone, on the warm off-white page',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    api = Api('http://test');
    api.dio.httpClientAdapter = MockApiAdapter(
        (request) => jsonResponse({'error': 'unauthorized'}, 401));
    AuthorizationSession.clear();
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await tester.pumpWidget(const DriverPilotApp());
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.light,
        reason: 'brief 7: light mode only, page is warm off-white');
    expect(app.darkTheme, isNull,
        reason: 'brief 7: light mode only, page is warm off-white');

    final scaffoldFinder = find.byType(Scaffold).first;
    final scaffold = tester.widget<Scaffold>(scaffoldFinder);
    final theme = Theme.of(tester.element(scaffoldFinder));
    expect(theme.brightness, Brightness.light,
        reason: 'brief 7: light mode only, page is warm off-white');
    expect(scaffold.backgroundColor ?? theme.scaffoldBackgroundColor,
        NvColors.page,
        reason: 'brief 7: light mode only, page is warm off-white');
    expect(theme.textTheme.bodyMedium?.fontFeatures,
        contains(const FontFeature.tabularFigures()),
        reason: 'numbers in body text line up in columns (tabular figures)');
    expect(tester.takeException(), isNull);
  });
}
