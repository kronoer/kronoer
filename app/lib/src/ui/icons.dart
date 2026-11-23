import 'package:flutter/widgets.dart';
import 'package:vector_graphics/vector_graphics.dart';

enum KIcons {
  arrowLeft('arrow-left'),
  arrowUTurnLeft('arrow-u-turn-left'),
  bell('bell'),
  bin('bin-2'),
  book('book'),

  /// Made for Kronoer, in vectors/icons/custom/: Keyline's book with an arrow
  /// in the corner, the way it draws book-plus.
  bookArrowRight('book-arrow-right'),
  calendar('calendar'),
  camera('camera'),
  check('check'),
  chevronRight('chevron-right'),
  clock('clock'),
  copy('copy'),
  download('download'),
  fingerprintPattern('fingerprint-pattern'),
  image('image'),
  imageOff('image-off'),
  info('info'),
  language('language'),
  lock('lock'),
  moreVertical('more-vertical'),
  pen('pen'),
  pin('pin'),
  pinOff('pin-off'),
  plus('plus'),
  search('search'),
  settings('settings'),
  star('star'),
  starOff('star-off'),
  swatchBook('swatch-book'),

  /// Made for Kronoer, in vectors/icons/custom/: a stack of cards, the newest
  /// in front, drawn the way Keyline draws its own.
  timeline('timeline'),

  /// Made for Kronoer, in vectors/icons/custom/: [timeline] with the ribbon of
  /// Keyline's book on the front card, for a Book's place in the Timeline.
  timelineBook('timeline-book'),
  upload('upload'),
  x('x');

  const KIcons(this.file);

  final String file;
}

class KIcon extends StatelessWidget {
  const KIcon(
    this.icon, {
    super.key,
    this.filled = false,
    this.size,
    this.color,
    this.semanticLabel,
  });

  final KIcons icon;
  final bool filled;
  final double? size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final size = this.size ?? theme.size ?? 24;
    final base = color ?? theme.color!;
    final tint = base.withValues(alpha: base.a * (theme.opacity ?? 1));
    final graphic = ExcludeSemantics(
      child: VectorGraphic(
        loader: AssetBytesLoader(
          'assets/icons/${filled ? 'fill' : 'stroke'}/${icon.file}.vec',
        ),
        width: size,
        height: size,
        colorFilter: ColorFilter.mode(tint, BlendMode.srcIn),
      ),
    );
    return semanticLabel == null
        ? graphic
        : Semantics(label: semanticLabel, child: graphic);
  }
}
