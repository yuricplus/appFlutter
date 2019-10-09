// Copyright 2015 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';

import 'test_widgets.dart';

class ProbeWidget extends StatefulWidget {
  @override
  ProbeWidgetState createState() => ProbeWidgetState();
}

class ProbeWidgetState extends State<ProbeWidget> {
  static int buildCount = 0;

  @override
  void initState() {
    super.initState();
    setState(() { });
  }

  @override
  void didUpdateWidget(ProbeWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    setState(() { });
  }

  @override
  Widget build(BuildContext context) {
    setState(() { });
    buildCount++;
    return Container();
  }
}

class BadWidget extends StatelessWidget {
  const BadWidget(this.parentState);

  final BadWidgetParentState parentState;

  @override
  Widget build(BuildContext context) {
    parentState._markNeedsBuild();
    return Container();
  }
}

class BadWidgetParent extends StatefulWidget {
  @override
  BadWidgetParentState createState() => BadWidgetParentState();
}

class BadWidgetParentState extends State<BadWidgetParent> {
  void _markNeedsBuild() {
    setState(() {
      // Our state didn't really change, but we're doing something pathological
      // here to trigger an interesting scenario to test.
    });
  }

  @override
  Widget build(BuildContext context) {
    return BadWidget(this);
  }
}

class BadDisposeWidget extends StatefulWidget {
  @override
  BadDisposeWidgetState createState() => BadDisposeWidgetState();
}

class BadDisposeWidgetState extends State<BadDisposeWidget> {
  @override
  Widget build(BuildContext context) {
    return Container();
  }

  @override
  void dispose() {
    setState(() { /* This is invalid behavior. */ });
    super.dispose();
  }
}

class StatefulWrapper extends StatefulWidget {
  const StatefulWrapper({
    Key key,
    this.child,
  }) : super(key: key);

  final Widget child;

  @override
  StatefulWrapperState createState() => StatefulWrapperState();
}

class StatefulWrapperState extends State<StatefulWrapper> {

  void trigger() {
    setState(() { built = null; });
  }

  int built;
  int oldBuilt;

  static int buildId = 0;

  @override
  Widget build(BuildContext context) {
    buildId += 1;
    built = buildId;
    return widget.child;
  }
}

class Wrapper extends StatelessWidget {
  const Wrapper({
    Key key,
    this.child,
  }) : super(key: key);

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return child;
  }
}

void main() {
  testWidgets('Legal times for setState', (WidgetTester tester) async {
    final GlobalKey flipKey = GlobalKey();
    expect(ProbeWidgetState.buildCount, equals(0));
    await tester.pumpWidget(ProbeWidget());
    expect(ProbeWidgetState.buildCount, equals(1));
    await tester.pumpWidget(ProbeWidget());
    expect(ProbeWidgetState.buildCount, equals(2));
    await tester.pumpWidget(FlipWidget(
      key: flipKey,
      left: Container(),
      right: ProbeWidget(),
    ));
    expect(ProbeWidgetState.buildCount, equals(2));
    final FlipWidgetState flipState1 = flipKey.currentState;
    flipState1.flip();
    await tester.pump();
    expect(ProbeWidgetState.buildCount, equals(3));
    final FlipWidgetState flipState2 = flipKey.currentState;
    flipState2.flip();
    await tester.pump();
    expect(ProbeWidgetState.buildCount, equals(3));
    await tester.pumpWidget(Container());
    expect(ProbeWidgetState.buildCount, equals(3));
  });

  testWidgets('Setting parent state during build is forbidden', (WidgetTester tester) async {
    await tester.pumpWidget(BadWidgetParent());
    expect(tester.takeException(), isFlutterError);
    await tester.pumpWidget(Container());
  });

  testWidgets('Setting state during dispose is forbidden', (WidgetTester tester) async {
    await tester.pumpWidget(BadDisposeWidget());
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(Container());
    expect(tester.takeException(), isNotNull);
  });

  testWidgets('Dirty element list sort order', (WidgetTester tester) async {
    final GlobalKey key1 = GlobalKey(debugLabel: 'key1');
    final GlobalKey key2 = GlobalKey(debugLabel: 'key2');

    bool didMiddle = false;
    Widget middle;
    final List<StateSetter> setStates = <StateSetter>[];
    Widget builder(BuildContext context, StateSetter setState) {
      setStates.add(setState);
      final bool returnMiddle = !didMiddle;
      didMiddle = true;
      return Wrapper(
        child: Wrapper(
          child: StatefulWrapper(
            child: returnMiddle ? middle : Container(),
          ),
        ),
      );
    }
    final Widget part1 = Wrapper(
      child: KeyedSubtree(
        key: key1,
        child: StatefulBuilder(
          builder: builder,
        ),
      ),
    );
    final Widget part2 = Wrapper(
      child: KeyedSubtree(
        key: key2,
        child: StatefulBuilder(
          builder: builder,
        ),
      ),
    );

    middle = part2;
    await tester.pumpWidget(part1);

    for (StatefulWrapperState state in tester.stateList<StatefulWrapperState>(find.byType(StatefulWrapper))) {
      expect(state.built, isNotNull);
      state.oldBuilt = state.built;
      state.trigger();
    }
    for (StateSetter setState in setStates)
      setState(() { });

    StatefulWrapperState.buildId = 0;
    middle = part1;
    didMiddle = false;
    await tester.pumpWidget(part2);

    for (StatefulWrapperState state in tester.stateList<StatefulWrapperState>(find.byType(StatefulWrapper))) {
      expect(state.built, isNotNull);
      expect(state.built, isNot(equals(state.oldBuilt)));
    }

  });
}
