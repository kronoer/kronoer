import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:kronoer/l10n/app_localizations.dart';
import 'package:kronoer/src/books/book_providers.dart';
import 'package:kronoer/src/entries/entry.dart';
import 'package:kronoer/src/entries/entry_deletion.dart';
import 'package:kronoer/src/entries/entry_repository.dart';
import 'package:kronoer/src/entries/entry_image.dart';
import 'package:kronoer/src/entries/image_processing.dart';
import 'package:kronoer/src/entries/photo_picker.dart';
import 'package:kronoer/src/router.dart';
import 'package:kronoer/src/storage/storage.dart';
import 'package:kronoer/src/theme/bottom_bar_style.dart';
import 'package:kronoer/src/theme/tokens.dart';
import 'package:kronoer/src/theme/typography.dart';
import 'package:kronoer/src/ui/icons.dart';
import 'package:material_ui/material_ui.dart';

/// How many images one Entry can hold.
const maxImages = 20;

/// How long typing pauses before the Entry is saved.
const autosaveDelay = Duration(milliseconds: 600);

/// One Image in the editor: stored already, or picked and maybe still being
/// prepared.
class _EditorImage {
  _EditorImage.stored(String this.id);

  _EditorImage.picked();

  /// Set once the Image is stored.
  String? id;

  /// A picked Image once prepared, until it is stored.
  ProcessedImage? unsaved;

  /// What the editor shows of a picked Image, so storing it does not reload
  /// it.
  Uint8List? thumbnail;

  bool get isReady => id != null || unsaved != null;
}

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
  var _images = <_EditorImage>[];

  /// Picked photos still being prepared.
  final _preparing = <Future<void>>{};

  /// Whether the gallery or camera is opening: a waiting tile holds the
  /// place the photos will land. It is no Image, so it is never saved.
  var _waitingForPicker = false;

  /// The Entry as last stored; null until the first save of a new Entry.
  Entry? _saved;
  var _loading = false;
  var _dirty = false;
  var _leaving = false;
  Timer? _debounce;
  Future<void> _writes = Future.value();

  bool get _isEmpty => _text.text.trim().isEmpty && _images.isEmpty;

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
      _images = [for (final id in entry.imageIds) _EditorImage.stored(id)];
      _loading = false;
    });
  }

  @override
  void dispose() {
    // Leaving through a route change that skipped [_leave] still saves,
    // with the photos still being prepared.
    if (!_leaving) unawaited(_settled().then((_) => _save()));
    _debounce?.cancel();
    _lifecycle.dispose();
    _text.dispose();
    super.dispose();
  }

  /// Waits for every photo being prepared.
  Future<void> _settled() async {
    while (_preparing.isNotEmpty) {
      await Future.wait([..._preparing]);
    }
  }

  void _changed() {
    _dirty = true;
    _debounce?.cancel();
    _debounce = Timer(autosaveDelay, _save);
    if (mounted) setState(() {});
  }

  /// Saves what changed, after any save still running.
  Future<void> _save() {
    _debounce?.cancel();
    return _writes = _writes.then((_) => _write());
  }

  Future<void> _write() async {
    // An empty Entry is not stored; leaving discards it.
    if (!_dirty || _isEmpty) return;
    // Photos still being prepared are saved once ready.
    final images = _images.where((image) => image.isReady).toList();
    if (_text.text.trim().isEmpty && images.isEmpty) return;
    _dirty = false;

    final drafts = [
      for (final image in images)
        if (image.id case final id?)
          KeptImage(id)
        else
          NewImage(image.unsaved!),
    ];
    final saved = _saved;
    try {
      final Entry stored;
      if (saved == null) {
        stored = await _entries.createEntry(
          bookId: widget.bookId,
          text: _text.text,
          dateTime: _dateTime,
          images: drafts.cast<NewImage>(),
        );
      } else {
        stored = await _entries.updateEntry(
          saved.copyWith(text: _text.text, dateTime: _dateTime),
          images: drafts,
        );
      }
      // The Images are stored in the order sent, so new ones get their IDs
      // by place.
      for (final (i, image) in images.indexed) {
        if (image.id == null) {
          image
            ..id = stored.imageIds[i]
            ..unsaved = null;
        }
      }
      _saved = stored;
    } catch (error) {
      // Try again with the next change or on leaving.
      _dirty = true;
      debugPrint('Entry not saved: $error');
    }
    if (mounted) setState(() {});
  }

  /// Saves, discards an empty Entry, and closes the editor.
  ///
  /// Editing an Entry returns to its read view, which opened the editor, or
  /// past it when the Entry was emptied. A new Entry opens in the read view
  /// after "Selesai", and otherwise returns to the Book.
  Future<void> _leave({required bool done}) async {
    if (_leaving) return;
    _leaving = true;

    await _settled();
    await _save();
    var saved = _saved;
    if (saved != null && _isEmpty) {
      await _entries.deleteEntry(saved.id);
      saved = null;
    }
    if (!mounted) return;

    if (widget.entryId != null) {
      closeEntryScreens(context, widget.bookId, screens: saved == null ? 2 : 1);
    } else if (saved != null && done) {
      context.go(Routes.entry(widget.bookId, saved.id));
    } else {
      context.go(Routes.book(widget.bookId));
    }
  }

  Future<void> _delete() async {
    _leaving = true;
    await _settled();
    await _save();
    final saved = _saved;
    if (!mounted || saved == null) return;
    // Editing, the read view under the editor goes too.
    deleteEntryWithUndo(
      context,
      ref,
      saved,
      screens: widget.entryId != null ? 2 : 1,
    );
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

  void _removeImage(_EditorImage image) {
    _images = [..._images]..remove(image);
    _changed();
  }

  void _moveImage(int from, int to) {
    final images = [..._images];
    images.insert(to, images.removeAt(from));
    _images = images;
    _changed();
  }

  Future<void> _addPhotos() async {
    final l10n = AppLocalizations.of(context);
    final left = maxImages - _images.length;
    if (left <= 0) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.imageLimit(maxImages))));
      return;
    }

    final source = await _showPhotoSheet(context);
    if (source == null || !mounted) return;
    final picker = ref.read(photoPickerProvider);
    // The picker can take a moment to open.
    setState(() => _waitingForPicker = true);
    final List<PickedPhoto> photos;
    try {
      photos = switch (source) {
        _PhotoSource.gallery => await picker.gallery(limit: left),
        _PhotoSource.camera => [?await picker.camera()],
      };
    } on Exception catch (error) {
      debugPrint('No photo picked: $error');
      return;
    } finally {
      // Replaced below by the picked photos, in the same frame, or gone.
      _waitingForPicker = false;
      if (mounted) setState(() {});
    }

    // The picker may give more than asked for; the rest are dropped.
    final room = maxImages - _images.length;
    for (final photo in photos.skip(room)) {
      unawaited(photo.discard());
    }
    if (!mounted) {
      photos.take(room).forEach((photo) => unawaited(photo.discard()));
      return;
    }
    final prepare = ref.read(imageProcessorProvider);
    for (final photo in photos.take(room)) {
      final image = _EditorImage.picked();
      _images = [..._images, image];
      late final Future<void> work;
      work = _prepare(
        image,
        photo,
        prepare,
      ).whenComplete(() => _preparing.remove(work));
      _preparing.add(work);
    }
    setState(() {});
  }

  /// Prepares a picked photo, then deletes the file it came in.
  Future<void> _prepare(
    _EditorImage image,
    PickedPhoto photo,
    Future<ProcessedImage> Function(Uint8List bytes) prepare,
  ) async {
    try {
      final ready = await prepare(await photo.read());
      image
        ..unsaved = ready
        ..thumbnail = ready.thumbnail;
    } on Object catch (error) {
      debugPrint('Photo not added: $error');
      _images = [..._images]..remove(image);
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(l10n.imageNotAdded)));
        setState(() {});
      }
      return;
    } finally {
      await photo.discard();
    }
    // Taken out while it was being prepared.
    if (!_images.contains(image)) return;
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
                    imageCount: _images.length,
                    saved: _saved != null && !_dirty,
                    onAddPhoto: _addPhotos,
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
          if (_images.isNotEmpty || _waitingForPicker)
            _ImageRow(
              entryId: _saved?.id,
              images: _images,
              waiting: _waitingForPicker,
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
    required this.entryId,
    required this.images,
    required this.waiting,
    required this.onRemove,
    required this.onMove,
  });

  /// Null until the Entry is first stored.
  final String? entryId;
  final List<_EditorImage> images;

  /// Shows a waiting tile after the images, while the picker opens. It
  /// cannot be moved or taken out.
  final bool waiting;
  final ValueChanged<_EditorImage> onRemove;
  final void Function(int from, int to) onMove;

  Widget _thumbnail(_EditorImage image) {
    if (image.thumbnail case final bytes?) {
      return Image.memory(
        bytes,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => const BrokenImage(),
      );
    }
    if ((entryId, image.id) case (final entryId?, final imageId?)) {
      return EntryImage(entryId: entryId, imageId: imageId);
    }
    return const ImageLoading(busy: true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: 96,
      child: ReorderableListView(
        scrollDirection: Axis.horizontal,
        onReorderItem: onMove,
        footer: waiting
            ? SizedBox.square(
                key: const ValueKey('waiting'),
                dimension: 96,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.m),
                  child: const ImageLoading(busy: true),
                ),
              )
            : null,
        children: [
          for (final image in images)
            Padding(
              key: ObjectKey(image),
              padding: const EdgeInsets.only(right: Space.s),
              child: SizedBox.square(
                dimension: 96,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(Radii.m),
                      child: _thumbnail(image),
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
                          onTap: () => onRemove(image),
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
  const _BottomBar({
    required this.imageCount,
    required this.saved,
    required this.onAddPhoto,
  });

  final int imageCount;
  final bool saved;

  /// At the limit too, where it explains the limit.
  final VoidCallback onAddPhoto;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return DecoratedBox(
      decoration: theme.extension<BottomBarStyle>()!.decoration,
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
                onPressed: onAddPhoto,
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

enum _PhotoSource { gallery, camera }

/// "Galeri" and "Kamera"; null when closed without a choice.
Future<_PhotoSource?> _showPhotoSheet(BuildContext context) {
  final l10n = AppLocalizations.of(context);

  return showModalBottomSheet<_PhotoSource>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const KIcon(KIcons.image),
            title: Text(l10n.gallery),
            onTap: () => Navigator.pop(context, _PhotoSource.gallery),
          ),
          ListTile(
            leading: const KIcon(KIcons.camera),
            title: Text(l10n.camera),
            onTap: () => Navigator.pop(context, _PhotoSource.camera),
          ),
          const SizedBox(height: Space.s),
        ],
      ),
    ),
  );
}
