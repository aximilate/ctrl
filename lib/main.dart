import 'package:flutter/widgets.dart';
import 'package:url_strategy/url_strategy.dart';

import 'src/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  setPathUrlStrategy();
  runApp(const CtrlChatAppRoot());
}
