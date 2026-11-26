import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';

/// Initialize Magic framework for tests.
///
/// Call this in setUpAll() for tests that need Magic services like Log, Http.
Future<void> initMagicForTests() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Magic.init(configFactories: []);
}

/// The semantics nodes assistive technology sees, merged ones left out.
///
/// The caller holds a `SemanticsHandle` from `tester.ensureSemantics()`, or the
/// tree is not built and this returns nothing.
List<SemanticsData> publishedSemanticsNodes(WidgetTester tester) {
  final List<SemanticsData> nodes = <SemanticsData>[];
  final SemanticsNode? root =
      tester.binding.renderViews.first.owner?.semanticsOwner?.rootSemanticsNode;

  void collect(SemanticsNode node) {
    if (!node.isMergedIntoParent) nodes.add(node.getSemanticsData());
    node.visitChildren((SemanticsNode child) {
      collect(child);
      return true;
    });
  }

  if (root != null) collect(root);

  return nodes;
}
