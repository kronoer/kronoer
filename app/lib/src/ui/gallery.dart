import 'package:material_ui/material_ui.dart';

import '../theme/tokens.dart';
import '../theme/typography.dart';
import 'banner.dart';
import 'buttons.dart';
import 'card.dart';
import 'empty_state.dart';
import 'icons.dart';

class Gallery extends StatelessWidget {
  const Gallery({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Components')),
      body: ListView(
        padding: const EdgeInsets.all(Space.l),
        children: [
          _Section(
            'Buttons',
            Wrap(
              spacing: Space.l,
              runSpacing: Space.l,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton(onPressed: () {}, child: const Text('Aktifkan')),
                FilledButton.tonalIcon(
                  onPressed: () {},
                  icon: const KIcon(KIcons.image),
                  label: const Text('Tambah foto'),
                ),
                TextButton(onPressed: () {}, child: const Text('Batal')),
                TextButton(
                  onPressed: () {},
                  style: destructiveTextButton(scheme),
                  child: const Text('Hapus'),
                ),
                IconButton(
                  onPressed: () {},
                  tooltip: 'Pengaturan',
                  icon: const KIcon(KIcons.settings),
                ),
                // Several FABs on one screen need their own hero tags.
                FloatingActionButton(
                  heroTag: null,
                  onPressed: () {},
                  tooltip: 'Tulis Entry',
                  child: const KIcon(KIcons.pen),
                ),
                FloatingActionButton.extended(
                  heroTag: null,
                  onPressed: () {},
                  icon: const KIcon(KIcons.plus),
                  label: const Text('Buat Book'),
                ),
              ],
            ),
          ),
          _Section(
            'Inputs and controls',
            Column(
              spacing: Space.l,
              children: [
                const TextField(
                  decoration: InputDecoration(labelText: 'Nama Book'),
                ),
                TextFormField(
                  autofocus: true,
                  initialValue: 'Resep Keluarga',
                  decoration: const InputDecoration(labelText: 'Nama Book'),
                ),
                const TextField(
                  decoration: InputDecoration(
                    labelText: 'Nama Book',
                    errorText: 'Nama Book wajib diisi',
                  ),
                ),
                Row(
                  spacing: Space.l,
                  children: [
                    Switch(value: true, onChanged: (_) {}),
                    Switch(value: false, onChanged: (_) {}),
                  ],
                ),
              ],
            ),
          ),
          _Section(
            'Cards and banners',
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.m,
              children: [
                const _BookCardSample(),
                const _EntryCardSample(),
                KBanner(
                  icon: KIcons.download,
                  title: 'Sudah 30 hari belum ekspor',
                  message: 'Ada 12 Entry baru sejak ekspor terakhir.',
                  dismissLabel: 'Nanti',
                  onDismiss: () {},
                  actionLabel: 'Ekspor',
                  onAction: () {},
                ),
                KBanner(
                  icon: KIcons.fingerprintPattern,
                  title: 'Lindungi Kronoer dengan sidik jari?',
                  message: 'Bisa diubah kapan saja di Pengaturan.',
                  dismissLabel: 'Nanti',
                  onDismiss: () {},
                  actionLabel: 'Aktifkan',
                  onAction: () {},
                  tone: BannerTone.suggestion,
                ),
              ],
            ),
          ),
          _Section(
            'Dialogs and feedback',
            Wrap(
              spacing: Space.l,
              runSpacing: Space.l,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.tonal(
                  onPressed: () => _showDeleteDialog(context),
                  child: const Text('Dialog'),
                ),
                FilledButton.tonal(
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Entry dihapus'),
                      action: SnackBarAction(
                        label: 'Urungkan',
                        onPressed: () {},
                      ),
                    ),
                  ),
                  child: const Text('Snackbar'),
                ),
                MenuAnchor(
                  menuChildren: [
                    MenuItemButton(
                      leadingIcon: const KIcon(KIcons.pen),
                      onPressed: () {},
                      child: const Text('Ganti nama'),
                    ),
                    MenuItemButton(
                      style: destructiveMenuItem(scheme),
                      leadingIcon: const KIcon(KIcons.bin),
                      onPressed: () {},
                      child: const Text('Hapus Book'),
                    ),
                  ],
                  builder: (context, controller, _) => IconButton(
                    onPressed: () => controller.isOpen
                        ? controller.close()
                        : controller.open(),
                    tooltip: 'Menu Book',
                    icon: const KIcon(KIcons.moreVertical),
                  ),
                ),
              ],
            ),
          ),
          const _Section(
            'Empty state',
            SizedBox(
              height: 480,
              child: EmptyState(
                title: 'Belum ada Entry',
                message: 'Tulis Entry pertama di Book ini.',
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus Book?'),
        content: const Text(
          'Hapus “Buku Saya” dan 24 Entry? Tidak bisa dibatalkan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: destructiveTextButton(scheme),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.child);

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.l,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _BookCardSample extends StatelessWidget {
  const _BookCardSample();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final muted = theme.colorScheme.onSurfaceVariant;
    final entry = theme.extension<EntryTextStyles>()!;

    return KCard(
      onTap: () {},
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 6,
        children: [
          Row(
            children: [
              Expanded(child: Text('Buku Saya', style: text.titleMedium)),
              Text('19.40', style: text.bodySmall?.copyWith(color: muted)),
            ],
          ),
          Text(
            'Pagi ini hujan turun pelan. Aku duduk di teras dengan kopi yang '
            'sudah dingin, menunggu kabar dari Ibu.',
            style: entry.entryPreviewSmall,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          Text('24 entry', style: text.bodySmall?.copyWith(color: muted)),
        ],
      ),
    );
  }
}

class _EntryCardSample extends StatelessWidget {
  const _EntryCardSample();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final date = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final entry = theme.extension<EntryTextStyles>()!;

    return KCard(
      onTap: () {},
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Senin, 16 Nov',
                  style: date?.copyWith(fontWeight: FontWeight.w500),
                ),
              ),
              Text('19.40', style: date),
            ],
          ),
          Text(
            'Pagi ini hujan turun pelan. Aku duduk di teras dengan kopi yang '
            'sudah dingin, menunggu kabar dari Ibu. Rasanya tenang, walau '
            'kepala masih penuh urusan minggu depan.',
            style: entry.entryPreview,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
          Container(
            height: 150,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(Radii.m),
            ),
            child: Text('Foto', style: date),
          ),
        ],
      ),
    );
  }
}
