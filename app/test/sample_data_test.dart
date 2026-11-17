import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kronoer/src/sample/sample_data.dart';
import 'package:kronoer/src/storage/storage.dart';
import 'package:kronoer/src/welcome/has_started.dart';

void main() {
  final today = DateTime(2026, 11, 17, 9);

  late ProviderContainer container;

  setUp(() async {
    container = ProviderContainer.test(
      overrides: await sampleOverrides(now: today),
    );
  });

  test('marks the app as started', () {
    expect(container.read(hasStartedProvider), isTrue);
  });

  test('has several Books, each with Entries', () async {
    final books = await container
        .read(bookRepositoryProvider)
        .watchBooks()
        .first;
    expect(books.length, greaterThan(1));

    for (final book in books) {
      final entries = await container
          .read(entryRepositoryProvider)
          .watchEntries(book.id)
          .first;
      expect(entries, isNotEmpty, reason: book.name);
    }
  });

  test('spreads Entries across several months, some with images', () async {
    final books = await container
        .read(bookRepositoryProvider)
        .watchBooks()
        .first;
    final entries = [
      for (final book in books)
        ...await container
            .read(entryRepositoryProvider)
            .watchEntries(book.id)
            .first,
    ];

    final months = {
      for (final e in entries) (e.dateTime.year, e.dateTime.month),
    };
    expect(months.length, greaterThanOrEqualTo(3));
    expect(entries.any((e) => e.imageIds.isNotEmpty), isTrue);
    expect(entries.every((e) => !e.dateTime.isAfter(today)), isTrue);
  });

  test('later writes use the real clock, not the sample one', () async {
    final books = container.read(bookRepositoryProvider);
    final before = DateTime.now();
    final book = await books.createBook('New');

    expect(book.lastActivityAt.isBefore(before), isFalse);
  });
}
