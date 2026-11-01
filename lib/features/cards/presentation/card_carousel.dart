import 'package:flutter/material.dart';
import '../../../core/theme/app_animations.dart';
import '../../../shared/models/models.dart';
import 'bank_card_widget.dart';

/// Horizontally swipeable cards; the focused card is full size, neighbours recede.
class CardCarousel extends StatefulWidget {
  const CardCarousel({super.key, required this.cards, this.onChanged});
  final List<BankCard> cards;
  final ValueChanged<int>? onChanged;

  @override
  State<CardCarousel> createState() => _CardCarouselState();
}

class _CardCarouselState extends State<CardCarousel> {
  final _controller = PageController(viewportFraction: 0.88);
  double _page = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final p = _controller.page ?? 0;
      if (p != _page) setState(() => _page = p);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = AppAnimations.reduced(context);
    return LayoutBuilder(
      builder: (context, box) {
        // Card is 1.586:1 inside a 0.88 viewport; leave room for the scale-up shadow.
        final height = box.maxWidth * 0.88 / 1.586 + 24;
        return SizedBox(
          height: height,
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.cards.length,
            clipBehavior: Clip.none,
            onPageChanged: widget.onChanged,
            itemBuilder: (_, i) {
              final focus = (1 - (_page - i).abs()).clamp(0.0, 1.0);
              final scale = reduced ? 1.0 : 0.92 + 0.08 * focus;
              return Center(
                child: Transform.scale(
                  scale: scale,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: RepaintBoundary(child: BankCardWidget(card: widget.cards[i])),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
