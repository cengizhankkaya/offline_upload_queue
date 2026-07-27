import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:offline_upload_queue_example/main.dart';

void main() {
  testWidgets('App starts and shows bottom navigation',
      (WidgetTester tester) async {
    await tester.pumpWidget(const OfflineUploadQueueDemoApp());
    expect(find.byType(NavigationBar), findsOneWidget);
  });
}
