import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:kronoer/l10n/app_localizations.dart';
import 'package:kronoer/src/books/book_providers.dart';
import 'package:kronoer/src/entries/entry.dart';
import 'package:kronoer/src/entries/entry_deletion.dart';
import 'package:kronoer/src/entries/entry_repository.dart';
import 'package:kronoer/src/entries/image_placeholder.dart';
import 'package:kronoer/src/router.dart';
import 'package:kronoer/src/storage/storage.dart';
import 'package:kronoer/src/theme/tokens.dart';
import 'package:kronoer/src/theme/typography.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:material_ui/material_ui.dart';

/// How many images one Entry can hold.
const maxImages = 20;

/// How long typing pauses before the Entry is saved.
const autosaveDelay = Duration(milliseconds: 600);

/// Writes a new Entry, or edits one when [entryId] is set. Saves as the user
/// types; leaving never asks. An Entry with no text and no images is
/// discarded when the editor closes.
class EntryEditorScreen extends ConsumerStatefulWidget {
  const EntryEditorScreen({
    required this.bookId,
    this.entryId,
    this.isFirst = false,
    super.key,
  });

  final String bookId;

  /// Null for a new Entry.
  final String? entryId;

  /// The very first Entry, right after Welcome: it gets its own placeholder.
  final bool isFirst;

  @override
  ConsumerState<EntryEditorScreen> createState() => _EntryEditorScreenState();
}

class _EntryEditorScreenState extends ConsumerState<EntryEditorScreen> {
  late final EntryRepository _entries = ref.read(entryRepositoryProvider);
  late final DateTime Function() _clock = ref.read(clockProvider);
  late final AppLifecycleListener _lifecycle;
  final _text = TextEditingController();

  late DateTime _dateTime = _clock();
  var _imageIds = <String>[];

  /// The Entry as last stored; null until the first save of a new Entry.
  Entry? _saved;
  var _loading = false;
  var _dirty = false;
  var _leaving = false;
  Timer? _debounce;
  Future<void> _writes = Future.value();

  bool get _isEmpty => _text.text.trim().isEmpty && _imageIds.isEmpty;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onHide: _save);
    final id = widget.entryId;
    if (id != null) {
      _loading = true;
      _load(id);
    }
  }

  Future<void> _load(String id) async {
    final entry = await _entries.watchEntry(id).first;
    if (!mounted) return;
    if (entry == null) {
      context.go(Routes.book(widget.bookId));
      return;
    }
    setState(() {
      _saved = entry;
      _text.text = entry.text;
      _dateTime = entry.dateTime;
      _imageIds = [...entry.imageIds];
      _loading = false;
    });
  }

  @override
  void dispose() {
    // Leaving through a route change that skipped [_leave] still saves.
    if (!_leaving) unawaited(_save());
    _debounce?.cancel();
    _lifecycle.dispose();
    _text.dispose();
    super.dispose();
  }

  void _changed() {
    _dirty = true;
    _debounce?.cancel();
    _debounce = Timer(autosaveDelay, _save);
    setState(() {});
  }

  /// Saves what changed, after any save still running.
  Future<void> _save() {
    _debounce?.cancel();
    return _writes = _writes.then((_) => _write());
  }

  Future<void> _write() async {
    // An empty Entry is not stored; leaving discards it.
    if (!_dirty || _isEmpty) return;
    _dirty = false;

    final saved = _saved;
    try {
      if (saved == null) {
        _saved = await _entries.createEntry(
          bookId: widget.bookId,
          text: _text.text,
          dateTime: _dateTime,
        );
      } else {
        final next = saved.copyWith(
          text: _text.text,
          dateTime: _dateTime,
          imageIds: List.unmodifiable(_imageIds),
        );
        await _entries.updateEntry(next);
        _saved = next;
      }
    } catch (error) {
      // Try again with the next change or on leaving.
      _dirty = true;
      debugPrint('Entry not saved: $error');
    }
    if (mounted) setState(() {});
  }

  /// Saves, discards an empty Entry, and closes the editor: to the read
  /// view after "Selesai" or when editing, otherwise back to the Book.
  Future<void> _leave({required bool done}) async {
    if (_leaving) return;
    _leaving = true;

    await _save();
    var saved = _saved;
    if (saved != null && _isEmpty) {
      await _entries.deleteEntry(saved.id);
      saved = null;
    }
    if (!mounted) return;

    if (saved != null && (done || widget.entryId != null)) {
      context.go(Routes.entry(widget.bookId, saved.id));
    } else {
      context.go(Routes.book(widget.bookId));
    }
  }

  Future<void> _delete() async {
    _leaving = true;
    await _save();
    final saved = _saved;
    if (!mounted || saved == null) return;
    deleteEntryWithUndo(context, ref, saved);
  }

  Future<void> _pickDateTime() async {
    final l10n = AppLocalizations.of(context);
    final now = _clock();
    final initial = _dateTime.isAfter(now) ? now : _dateTime;

    final date = await showDatePicker(
      context: context,
      helpText: l10n.entryDateQuestion,
      initialDate: initial,
      currentDate: now,
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      helpText: l10n.entryDateQuestion,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (!mounted) return;

    final picked = time ?? TimeOfDay.fromDateTime(initial);
    final dateTime = DateTime(
      date.year,
      date.month,
      date.day,
      picked.hour,
      picked.minute,
    );
    // Today at a later hour is still the future.
    _dateTime = dateTime.isAfter(now) ? now : dateTime;
    _changed();
  }

  void _removeImage(String id) {
    _imageIds = [..._imageIds]..remove(id);
    _changed();
  }

  void _moveImage(int from, int to) {
    final ids = [..._imageIds];
    final id = ids.removeAt(from);
    ids.insert(to, id);
    _imageIds = ids;
    _changed();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final book = ref.watch(bookProvider(widget.bookId)).value;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave(done: false);
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: Text(
            book?.name ?? '',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          actionsPadding: EdgeInsets.only(
            right: _saved == null ? Space.m : Space.xs,
          ),
          actions: [
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 20),
              ),
              onPressed: _loading ? null : () => _leave(done: true),
              child: Text(l10n.done),
            ),
            if (_saved != null) EntryMenu(onDelete: _delete),
          ],
        ),
        body: _loading
            ? const SizedBox.shrink()
            : Column(
                children: [
                  Expanded(child: _content(context)),
                  _BottomBar(
                    imageCount: _imageIds.length,
                    saved: _saved != null && !_dirty,
                  ),
                ],
              ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toString();
    final body = theme.extension<EntryTextStyles>()!.entryBody;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, Space.s, 20, Space.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: Space.l,
        children: [
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.fromLTRB(10, 0, 14, 0),
              foregroundColor: theme.colorScheme.onSurfaceVariant,
              side: BorderSide(color: theme.colorScheme.outlineVariant),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Radii.s),
              ),
              textStyle: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
                fontVariations: const [FontVariation.weight(500)],
              ),
            ),
            onPressed: _pickDateTime,
            icon: const KIcon(KIcons.calendar, size: 18),
            label: Text(
              '${DateFormat('EEEE, d MMM y', locale).format(_dateTime)} · '
              '${DateFormat.Hm(locale).format(_dateTime)}',
            ),
          ),
          Expanded(
            child: TextField(
              controller: _text,
              autofocus: widget.entryId == null,
              expands: true,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              enableIMEPersonalizedLearning: false,
              textAlignVertical: TextAlignVertical.top,
              style: body,
              onChanged: (_) => _changed(),
              // Not .collapsed: the theme's enabled and focused borders
              // would still draw a box around the page.
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: widget.isFirst
                    ? l10n.firstEntryPlaceholder
                    : l10n.entryPlaceholder,
                hintStyle: body.copyWith(
                  color: body.color?.withValues(alpha: 0.6),
                ),
              ),
            ),
          ),
          if (_imageIds.isNotEmpty)
            _ImageRow(
              imageIds: _imageIds,
              onRemove: _removeImage,
              onMove: _moveImage,
            ),
        ],
      ),
    );
  }
}

/// The Entry's images, in order. Drag one to move it; × takes it out.
class _ImageRow extends StatelessWidget {
  const _ImageRow({
    required this.imageIds,
    required this.onRemove,
    required this.onMove,
  });

  final List<String> imageIds;
  final ValueChanged<String> onRemove;
  final void Function(int from, int to) onMove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: 96,
      child: ReorderableListView(
        scrollDirection: Axis.horizontal,
        onReorderItem: onMove,
        children: [
          for (final id in imageIds)
            Padding(
              key: ValueKey(id),
              padding: const EdgeInsets.only(right: Space.s),
              child: SizedBox.square(
                dimension: 96,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(Radii.m),
                      child: ImagePlaceholder(id),
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Semantics(
                        container: true,
                        button: true,
                        label: l10n.removeImage,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => onRemove(id),
                          child: Padding(
                            padding: const EdgeInsets.all(Space.xs),
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: scheme.inverseSurface,
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: KIcon(
                                  KIcons.x,
                                  size: 16,
                                  color: scheme.onInverseSurface,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.imageCount, required this.saved});

  final int imageCount;
  final bool saved;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, 20),
          child: Row(
            spacing: Space.s,
            children: [
              FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.fromLTRB(Space.m, 0, 14, 0),
                ),
                onPressed: imageCount < maxImages
                    ? () => _showPhotoSheet(context)
                    : null,
                icon: const KIcon(KIcons.image, size: 20),
                label: Text(l10n.addPhoto),
              ),
              if (imageCount > 0)
                Text(l10n.imageCount(imageCount, maxImages), style: muted),
              const Spacer(),
              if (saved)
                Row(
                  spacing: 6,
                  children: [
                    KIcon(
                      KIcons.check,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    Text(l10n.saved, style: muted),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Galeri" and "Kamera". Neither does anything until images are picked
/// for real.
void _showPhotoSheet(BuildContext context) {
  final l10n = AppLocalizations.of(context);

  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const KIcon(KIcons.image),
            title: Text(l10n.gallery),
            onTap: () => Navigator.pop(context),
          ),
          ListTile(
            leading: const KIcon(KIcons.camera),
            title: Text(l10n.camera),
            onTap: () => Navigator.pop(context),
          ),
          const SizedBox(height: Space.s),
        ],
      ),
    ),
  );
}
