import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/widgets.dart';

/// My List's scroll view (r9), built lighter the frame the list lands in.
///
/// A scroll view builds the rows on screen and, ahead of a scroll, those in
/// the 250 px below them (its cache extent). When a long list lands, all of
/// them used to arrive in one frame with the board and the header. Until the
/// frame after [landed] first holds, the cache extent is 0, so that frame
/// builds only the rows on screen; the next one builds the rows below, before
/// anyone could scroll to them. The [slivers] are the same widgets in both
/// frames, so the second builds nothing else. At rest it is
/// `CustomScrollView(slivers: slivers)`, pixel for pixel.
class MyListLanding extends StatefulWidget {
  const MyListLanding({super.key, required this.landed, required this.slivers});

  /// Whether the list has arrived.
  final bool landed;
  final List<Widget> slivers;

  @override
  State<MyListLanding> createState() => _MyListLandingState();
}

class _MyListLandingState extends State<MyListLanding> {
  bool _settled = false;
  bool _settling = false;

  @override
  void initState() {
    super.initState();
    _settle();
  }

  @override
  void didUpdateWidget(MyListLanding oldWidget) {
    super.didUpdateWidget(oldWidget);
    _settle();
  }

  // Once the list has landed: the full cache extent from the next frame.
  void _settle() {
    if (_settled || _settling || !widget.landed) return;
    _settling = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _settled = true);
    });
  }

  @override
  Widget build(BuildContext context) => CustomScrollView(
        scrollCacheExtent:
            _settled ? null : const ScrollCacheExtent.pixels(0),
        slivers: widget.slivers,
      );
}
