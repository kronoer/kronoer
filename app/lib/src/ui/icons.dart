import 'package:flutter/widgets.dart';
import 'package:vector_graphics/vector_graphics.dart';

enum KIcons {
  arrowLeft('arrow-left'),
  bin('bin-2'),
  calendar('calendar'),
  check('check'),
  download('download'),
  fingerprintPattern('fingerprint-pattern'),
  image('image'),
  info('info'),
  language('language'),
  lock('lock'),
  moreVertical('more-vertical'),
  pen('pen'),
  plus('plus'),
  settings('settings'),
  swatchBook('swatch-book'),
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
          'assets/icons/${filled ? 'fill' : 'stroke'}/${icon.file}.svg',
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
