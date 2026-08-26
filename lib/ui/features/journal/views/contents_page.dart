import 'package:flutter/material.dart';

import '../../../../screens/contents_page.dart' as legacy;

/// Feature-owned table-of-contents boundary during the screen extraction.
class ContentsPage extends legacy.ContentsPage {
  const ContentsPage({
    super.key,
    required super.documents,
    required super.assetRepository,
    required super.onOpenPage,
    required super.onDeletePage,
    required VoidCallback onCreatePage,
  }) : super(onNewPage: onCreatePage);
}
