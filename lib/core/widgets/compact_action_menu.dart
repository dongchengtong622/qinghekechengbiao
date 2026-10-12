import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CompactMenuEntry {
  const CompactMenuEntry(this.value, this.icon, this.label, {this.tooltip});
  final String value;
  final IconData icon;
  final String label;
  final String? tooltip;
}

/// Fixed-size menu; only compositor transforms animate, never its layout size.
class CompactActionMenu extends StatefulWidget {
  const CompactActionMenu({
    super.key,
    required this.entries,
    required this.onSelected,
  });
  final List<CompactMenuEntry> entries;
  final ValueChanged<String> onSelected;
  @override
  State<CompactActionMenu> createState() => _CompactActionMenuState();
}

class _CompactActionMenuState extends State<CompactActionMenu> {
  final _anchor = GlobalKey();
  bool _open = false;
  Future<void> _show() async {
    if (_open) return;
    final navigator = Navigator.of(context);
    final overlay = navigator.overlay!.context.findRenderObject()! as RenderBox;
    final button = _anchor.currentContext!.findRenderObject()! as RenderBox;
    final anchor =
        button.localToGlobal(Offset.zero, ancestor: overlay) & button.size;
    final route = _ActionMenuRoute(
      anchor: anchor,
      entries: List.of(widget.entries),
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      barrierText: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    );
    _open = true;
    final result = await navigator.push<String>(route);
    // Avoid starting a new page while the closing menu is still animating.
    await route.completed;
    _open = false;
    if (mounted && result != null) widget.onSelected(result);
  }

  @override
  Widget build(BuildContext context) => IconButton(
    key: _anchor,
    tooltip: '更多',
    style: IconButton.styleFrom(overlayColor: Colors.transparent),
    onPressed: _show,
    icon: const Icon(Icons.more_horiz),
  );
}

class _ActionMenuRoute extends PopupRoute<String> {
  _ActionMenuRoute({
    required this.anchor,
    required this.entries,
    required this.themes,
    required this.barrierText,
  });
  final Rect anchor;
  final List<CompactMenuEntry> entries;
  final CapturedThemes themes;
  final String barrierText;
  @override
  Duration get transitionDuration => const Duration(milliseconds: 180);
  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 120);
  @override
  bool get barrierDismissible => true;
  @override
  Color? get barrierColor => null;
  @override
  String get barrierLabel => barrierText;
  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final media = MediaQuery.of(context);
    final width = (140 * media.textScaler.scale(1))
        .clamp(140, 280)
        .toDouble()
        .clamp(0, media.size.width - 16)
        .toDouble();
    final right = (media.size.width - anchor.right)
        .clamp(8, media.size.width - width - 8)
        .toDouble();
    final top = (anchor.bottom + 6)
        .clamp(
          media.padding.top + 8,
          media.size.height - media.padding.bottom - 56,
        )
        .toDouble();
    final curve = animation.drive(CurveTween(curve: Curves.easeOutCubic));
    final menu = themes.wrap(
      Material(
        key: const Key('compact_menu_surface'),
        elevation: 0,
        color: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final entry in entries) ...[
                if (entry.value == 'settings')
                  const Divider(height: 10, indent: 12, endIndent: 12),
                InkWell(
                  onTap: () => Navigator.of(context).pop(entry.value),
                  splashFactory: NoSplash.splashFactory,
                  overlayColor: const WidgetStatePropertyAll(
                    Colors.transparent,
                  ),
                  child: SizedBox(
                    height: 44,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          if (entry.tooltip != null)
                            Tooltip(
                              message: entry.tooltip!,
                              child: Icon(entry.icon, size: 18),
                            )
                          else
                            Icon(entry.icon, size: 18),
                          const SizedBox(width: 10),
                          Flexible(
                            child: Text(
                              entry.label,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: Stack(
        children: [
          Positioned(
            right: right,
            top: top,
            width: width,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: media.size.height - media.padding.bottom - top - 8,
              ),
              child: FadeTransition(
                opacity: curve,
                child: ScaleTransition(
                  alignment: Alignment.topRight,
                  scale: Tween<double>(begin: .94, end: 1).animate(curve),
                  child: RepaintBoundary(child: menu),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}
