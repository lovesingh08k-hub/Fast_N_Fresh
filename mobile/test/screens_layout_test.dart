import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:pwp_pos/core/theme/app_colors.dart';
import 'package:pwp_pos/models/user.dart';
import 'package:pwp_pos/providers/auth_provider.dart';
import 'package:pwp_pos/screens/pos/new_order_screen.dart';
import 'package:pwp_pos/screens/settings/more_screen.dart';

/// Renders whole screens at small phone sizes with an enlarged system font,
/// in light and dark mode. Any RenderFlex overflow fails the test.
Future<void> pumpScreen(
  WidgetTester tester,
  Widget screen, {
  required Size size,
  double textScale = 1.3,
  AuthProvider? auth,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  Widget app = MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: size, textScaler: TextScaler.linear(textScale)),
      child: screen,
    ),
  );
  if (auth != null) {
    app = ChangeNotifierProvider<AuthProvider>.value(value: auth, child: app);
  }
  await tester.pumpWidget(app);
  await tester.pump();
}

AuthProvider authAs(String role) {
  return AuthProvider()
    ..currentUser = AppUser(
      id: 'u1',
      name: 'Administrator Long Name',
      username: 'admin',
      phone: '9999999999',
      role: role,
      status: 'active',
    );
}

void main() {
  const sizes = [Size(320, 640), Size(360, 760), Size(412, 900)];

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';

    group('NewOrderScreen ($mode)', () {
      for (final size in sizes) {
        testWidgets('fits at ${size.width.toInt()}dp', (tester) async {
          AppColors.setDarkMode(dark);
          await pumpScreen(tester, const NewOrderScreen(), size: size, auth: authAs('admin'));
          expect(tester.takeException(), isNull);
          expect(find.text('Dine-In'), findsOneWidget);
          // Lower cards are built lazily; scroll to them on short screens.
          for (final label in ['Takeaway', 'Delivery']) {
            await tester.scrollUntilVisible(find.text(label), 200);
            expect(find.text(label), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
        });
      }
    });

    group('MoreScreen ($mode)', () {
      for (final role in ['admin', 'manager', 'staff']) {
        for (final size in sizes) {
          testWidgets('$role fits at ${size.width.toInt()}dp', (tester) async {
            AppColors.setDarkMode(dark);
            await pumpScreen(tester, const MoreScreen(),
                size: size, auth: authAs(role));
            expect(tester.takeException(), isNull);
            expect(find.text('More'), findsOneWidget);
          });
        }
      }

      testWidgets('admin sees admin-only tools', (tester) async {
        AppColors.setDarkMode(dark);
        await pumpScreen(tester, const MoreScreen(),
            size: const Size(412, 2400), auth: authAs('admin'));
        expect(find.text('Settings'), findsOneWidget);
        expect(find.text('Expenses'), findsOneWidget);
        // Removed from More: Bills lives in the bottom bar, Audit Log is gone.
        expect(find.text('Audit Log'), findsNothing);
        expect(find.text('Bills'), findsNothing);
      });

      testWidgets('staff does not see admin tools', (tester) async {
        AppColors.setDarkMode(dark);
        await pumpScreen(tester, const MoreScreen(),
            size: const Size(412, 2400), auth: authAs('staff'));
        expect(find.text('Settings'), findsNothing);
        expect(find.text('Expenses'), findsNothing);
        expect(find.text('MY TOOLS'), findsOneWidget);
      });
    });
  }
}
