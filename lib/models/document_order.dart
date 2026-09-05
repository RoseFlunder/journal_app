import 'document.dart';

int compareDocumentCreation(EntryDocument a, EntryDocument b) {
  final date = a.createdAt.compareTo(b.createdAt);
  return date == 0 ? a.id.compareTo(b.id) : date;
}

List<EntryDocument> chronologicalDocuments(Iterable<EntryDocument> documents) =>
    List<EntryDocument>.unmodifiable(
      documents.toList()..sort(compareDocumentCreation),
    );
