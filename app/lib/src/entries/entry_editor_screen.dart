import 'dart:async';

import 'package:flutter/services.dart';
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
import 'package:kronoer/src/entries/text_style_editing.dart';
import 'package:kronoer/src/entries/text_styles.dart';
import 'package:kronoer/src/reminder/writing_reminder.dart';
import 'package:kronoer/src/router.dart';
import 'package:kronoer/src/rust/api/store.dart' show countWords;
import 'package:kronoer/src/storage/storage.dart';
import 'package:kronoer/src/theme/bottom_bar_style.dart';
import 'package:kronoer/src/theme/tokens.dart';
import 'package:kronoer/src/theme/typography.dart';
import 'package:kronoer/src/trash/trash.dart';
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
  late final TrashRepository _trash = ref.read(trashRepositoryProvider);
  late final DateTime Function() _clock = ref.read(clockProvider);
  late final WritingReminderNotifier _reminder;
  late final AppLifecycleListener _lifecycle;
  final _text = StyledTextController();

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
    // Read now: an Entry can be created after the editor is gone.
    _reminder = ref.read(writingReminderProvider.notifier);
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
        unawaited(_reminder.entryCreated());
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
      await _trash.deleteForever(entryIds: [saved.id]);
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
                    wordCount: countWords(text: _text.text),
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
              inputFormatters: const [ListContinuation()],
              contextMenuBuilder: _textMenu,
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

  /// The system's text selection menu, with the Text styles after its own
  /// items while text is selected.
  Widget _textMenu(BuildContext context, EditableTextState editable) {
    final l10n = AppLocalizations.of(context);
    final value = editable.textEditingValue;

    ContextMenuButtonItem item(
      String label,
      TextEditingValue Function(TextEditingValue value) toggle,
    ) => ContextMenuButtonItem(
      label: label,
      onPressed: () {
        editable.userUpdateTextEditingValue(
          toggle(editable.textEditingValue),
          SelectionChangedCause.toolbar,
        );
        editable.hideToolbar();
      },
    );

    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editable.contextMenuAnchors,
      buttonItems: [
        ...editable.contextMenuButtonItems,
        if (value.selection.isValid && !value.selection.isCollapsed) ...[
          item(l10n.styleBold, (v) => toggleInlineStyle(v, InlineStyle.bold)),
          item(
            l10n.styleItalic,
            (v) => toggleInlineStyle(v, InlineStyle.italic),
          ),
          item(
            l10n.styleStrikethrough,
            (v) => toggleInlineStyle(v, InlineStyle.strikethrough),
          ),
          item(l10n.styleMonospace, toggleMonospaceBlock),
          item(l10n.styleCode, (v) => toggleInlineStyle(v, InlineStyle.code)),
          item(
            l10n.styleBulletedList,
            (v) => toggleLineStyle(v, LineStyle.bullet),
          ),
          item(
            l10n.styleNumberedList,
            (v) => toggleLineStyle(v, LineStyle.numbered),
          ),
          item(l10n.styleQuote, (v) => toggleLineStyle(v, LineStyle.quote)),
        ],
      ],
    );
  }
}

/// The Entry's images, in order. × takes one out.
///
/// A long press lifts an Image to move it: it vibrates like a long press,
/// grows a little with a soft shadow, and ticks lightly each time it passes
/// into a new place. TalkBack moves it with the list's own move actions.
class _ImageRow extends StatefulWidget {
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

  @override
  State<_ImageRow> createState() => _ImageRowState();
}

class _ImageRowState extends State<_ImageRow> {
  static const _size = 96.0;

  /// One Image and the gap after it: how far a lifted Image moves to pass
  /// into the next place.
  static const _extent = _size + Space.s;

  final _scroll = ScrollController();

  /// Where the pointer is along the row.
  double _pointer = 0;

  /// The lifted Image's own place, the place it would drop into now, and
  /// where the pointer and the row's scroll were when it was lifted.
  int? _from;
  int _place = 0;
  double _startPointer = 0;
  double _startScroll = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_moved);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _lifted(int index) {
    unawaited(Feedback.forLongPress(context));
    _from = index;
    _place = index;
    _startPointer = _pointer;
    _startScroll = _scroll.hasClients ? _scroll.offset : 0;
  }

  void _dropped(int _) => _from = null;

  /// Ticks when the lifted Image passes into a new place: as the list
  /// decides, by half an Image either way, with every Image the same width.
  void _moved() {
    final from = _from;
    if (from == null) return;
    final scrolled = _scroll.hasClients ? _scroll.offset - _startScroll : 0.0;
    final moved = _pointer - _startPointer + scrolled;
    final place = (from + (moved / _extent).round()).clamp(
      0,
      widget.images.length - 1,
    );
    if (place == _place) return;
    _place = place;
    unawaited(HapticFeedback.selectionClick());
  }

  void _pointerAt(PointerEvent event) {
    _pointer = event.position.dx;
    _moved();
  }

  /// The lifted Image: grown about 5% over the first 150 ms of the lift,
  /// with a soft shadow on its rounded corners and no ×. With reduced
  /// motion it only gets the shadow.
  Widget _liftedImage(Widget child, int index, Animation<double> animation) {
    final scheme = Theme.of(context).colorScheme;
    final grows = !MediaQuery.disableAnimationsOf(context);
    final image = widget.images[index];

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        // The lift animates over 250 ms; this is its first 150.
        final t = Curves.easeOut.transform(
          (animation.value / 0.6).clamp(0.0, 1.0),
        );
        return Padding(
          padding: const EdgeInsets.only(right: Space.s),
          child: Transform.scale(
            scale: grows ? 1 + 0.05 * t : 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Radii.m),
                boxShadow: [
                  BoxShadow(
                    color: scheme.shadow.withValues(alpha: 0.3 * t),
                    blurRadius: 16 * t,
                    offset: Offset(0, 6 * t),
                  ),
                ],
              ),
              child: _ImageTile(
                key: const ValueKey('lifted'),
                entryId: widget.entryId,
                image: image,
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _size,
      child: Listener(
        onPointerDown: _pointerAt,
        onPointerMove: _pointerAt,
        child: ReorderableListView(
          scrollDirection: Axis.horizontal,
          scrollController: _scroll,
          onReorderItem: widget.onMove,
          onReorderStart: _lifted,
          onReorderEnd: _dropped,
          proxyDecorator: _liftedImage,
          footer: widget.waiting
              ? SizedBox.square(
                  key: const ValueKey('waiting'),
                  dimension: _size,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.m),
                    child: const ImageLoading(busy: true),
                  ),
                )
              : null,
          children: [
            for (final image in widget.images)
              Padding(
                key: ObjectKey(image),
                padding: const EdgeInsets.only(right: Space.s),
                child: _ImageTile(
                  entryId: widget.entryId,
                  image: image,
                  onRemove: () => widget.onRemove(image),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One Image in the editor's row, with a × to take it out unless it is
/// lifted ([onRemove] null).
class _ImageTile extends StatelessWidget {
  const _ImageTile({
    required this.entryId,
    required this.image,
    this.onRemove,
    super.key,
  });

  final String? entryId;
  final _EditorImage image;
  final VoidCallback? onRemove;

  Widget _thumbnail() {
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
    final onRemove = this.onRemove;

    return SizedBox.square(
      dimension: _ImageRowState._size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.m),
            child: _thumbnail(),
          ),
          if (onRemove != null)
            Positioned(
              top: 0,
              right: 0,
              child: Semantics(
                container: true,
                button: true,
                label: l10n.removeImage,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onRemove,
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
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.imageCount,
    required this.wordCount,
    required this.saved,
    required this.onAddPhoto,
  });

  final int imageCount;

  /// The whole Entry's, by the rule the Book insight counts with; hidden
  /// at 0.
  final int wordCount;
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
              // The word count and the Image count stay whole; "Tersimpan"
              // gives way first, down to its ✓.
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (wordCount > 0)
                      Text(l10n.editorWordCount(wordCount), style: muted),
                    if (wordCount > 0 && saved) Text(' · ', style: muted),
                    if (saved) Flexible(child: _Saved(style: muted)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ✓ Tersimpan, or only the ✓ where the words do not fit.
class _Saved extends StatelessWidget {
  const _Saved({required this.style});

  final TextStyle? style;

  static const _icon = 16.0;
  static const _gap = 6.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final check = KIcon(
      KIcons.check,
      size: _icon,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final label = TextPainter(
          text: TextSpan(text: l10n.saved, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout();
        final fits = _icon + _gap + label.width <= constraints.maxWidth;
        label.dispose();
        if (!fits) return Semantics(label: l10n.saved, child: check);
        return Row(
          mainAxisSize: MainAxisSize.min,
          spacing: _gap,
          children: [
            check,
            Text(l10n.saved, style: style),
          ],
        );
      },
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
