import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:kronoer/src/theme/tokens.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:material_ui/material_ui.dart';

/// A row styled like the Settings tab's: a Keyline icon, a title, maybe a
/// hint under it, and maybe a control at the end, such as a switch.
///
/// The icon and the control line up with the title, not with the title and
/// the hint together. Without [onTap] the row is disabled; without [icon]
/// its space stays, so titles line up. A [destructive] row is in the error
/// color.
class SettingRow extends StatelessWidget {
  const SettingRow({
    required this.title,
    this.icon,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.destructive = false,
    super.key,
  });

  final KIcons? icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final titleStyle = theme.textTheme.bodyLarge!.copyWith(
      fontWeight: FontWeight.w500,
    );
    final subtitle = this.subtitle;
    final trailing = this.trailing;
    final icon = this.icon;

    // Like SwitchListTile: the row and its control are one thing to a
    // screen reader, and a tap anywhere on the row does what the control
    // does.
    return MergeSemantics(
      child: ListTile(
        enabled: onTap != null,
        onTap: onTap,
        minTileHeight: subtitle == null ? 56 : 64,
        contentPadding: const EdgeInsets.symmetric(horizontal: Space.xl),
        // The ListTile's icon color, disabled included, reaches the title.
        iconColor: destructive ? scheme.error : scheme.onSurfaceVariant,
        textColor: destructive ? scheme.error : null,
        titleTextStyle: titleStyle,
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TitleLine(
              style: titleStyle,
              child: SizedBox.square(
                dimension: 24,
                child: icon == null ? null : KIcon(icon),
              ),
            ),
            const SizedBox(width: Space.l),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: onTap == null
                            ? theme.disabledColor
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: Space.l),
              TitleLine(style: titleStyle, child: trailing),
            ],
          ],
        ),
      ),
    );
  }
}

/// Centers [child] on one line of text in [style], such as the first line of
/// a row's title, so an icon or a control lines up with the title rather
/// than with the title and the hint under it. A taller child, like a switch,
/// reaches past the line without making it taller.
class TitleLine extends StatelessWidget {
  const TitleLine({required this.style, required this.child, super.key});

  final TextStyle style;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final line =
        MediaQuery.textScalerOf(context).scale(style.fontSize!) *
        (style.height ?? 1);
    return SizedBox(
      height: line,
      child: OverflowBox(
        maxHeight: double.infinity,
        fit: OverflowBoxFit.deferToChild,
        child: child,
      ),
    );
  }
}
