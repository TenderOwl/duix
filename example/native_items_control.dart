import 'package:duix/dui.dart';
import 'package:duix/native.dart';

Future<void> main(List<String> args) async {
  final host = await SdlSkiaHost.initialize(
    diagnosticsEnabled: args.contains('--diagnostics'),
  );
  final items = ObservableCollection<String>.generate(
    100000,
    (index) => 'Элемент ${index + 1} из 100 000',
  );
  final panel = VirtualizingStackPanel<String>(
    itemsSource: items,
    estimatedItemExtent: 24,
    itemTemplate: (item) => Label(text: item)
      ..minHeight = 24
      ..maxHeight = 24,
  );
  final scrollViewer = ScrollViewer(
    content: panel,
    horizontalScrollBarVisibility: ScrollBarVisibility.disabled,
  );
  final header = Border(
    color: const Color(0xFFF4F4F4),
    padding: const EdgeInsets.all(12),
    content: Label(text: 'Виртуализированный список — 100 000 элементов'),
  );
  DockPanel.setDock(header, Dock.top);
  final window = Window(
    title: 'DUI — ItemsControl',
    width: 520,
    height: 360,
    content: DockPanel(children: [header, scrollViewer]),
  );

  final application = Application(host: host);
  try {
    if (args.contains('--smoke')) {
      await host.showWindow(window);
      window.updateLayout();
      if (panel.containerCount >= 50 ||
          panel.firstVisibleIndex != 0 ||
          scrollViewer.extentHeight < 2000000) {
        throw StateError(
          'Virtualization did not create the expected initial viewport.',
        );
      }
      final initialContainer = panel.elementAt(0)!;

      scrollViewer.scrollTo(vertical: 24 * 50000);
      window.updateLayout();
      var middleIndex = -1;
      UIElement? middleContainer;
      for (var index = panel.firstVisibleIndex;
          index <= panel.lastVisibleIndex;
          index++) {
        final candidate = panel.elementAt(index)!;
        if (candidate.bounds.bottom > scrollViewer.viewportRect.top &&
            candidate.bounds.top < scrollViewer.viewportRect.bottom) {
          middleIndex = index;
          middleContainer = candidate;
          break;
        }
      }
      if (middleContainer == null ||
          (middleIndex - 50000).abs() > 100 ||
          panel.containerCount >= 50 ||
          initialContainer.isMounted) {
        throw StateError(
          'Virtualization failed while scrolling to middle: '
          'index=$middleIndex, count=${panel.containerCount}, '
          'top=${middleContainer?.bounds.top}, '
          'viewport=${scrollViewer.viewportRect.top}, '
          'initialMounted=${initialContainer.isMounted}.',
        );
      }

      scrollViewer.scrollToEnd();
      window.updateLayout();
      final lastContainer = panel.elementAt(99999);
      if (lastContainer == null ||
          panel.containerCount >= 50 ||
          (lastContainer.bounds.bottom - scrollViewer.viewportRect.bottom)
                  .abs() >
              0.001) {
        throw StateError('Virtualization failed while scrolling to end.');
      }

      for (var frame = 0; frame < 3 && host.isOpen(window); frame++) {
        host.pumpEvents();
        host.presentWindow(window);
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }
      print(
        'Native items smoke passed: ${panel.containerCount} containers, '
        'extent=${scrollViewer.extentHeight.toStringAsFixed(1)}, '
        '3 frames rendered.',
      );
    } else {
      await application.run(window);
    }
  } finally {
    host.dispose();
  }
}
