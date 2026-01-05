import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/import_data.dart';

/// Service for interacting with arXiv API
class ArxivService {
  static const String _baseApiUrl = 'http://export.arxiv.org/api/query';
  static const String _pdfBaseUrl = 'https://arxiv.org/pdf/';

  /// Parse arXiv ID from various URL formats
  /// Supports:
  /// - https://arxiv.org/abs/1706.03762
  /// - https://arxiv.org/pdf/1706.03762.pdf
  /// - arxiv:1706.03762
  /// - 1706.03762
  static String? parseArxivId(String input) {
    input = input.trim();

    // Pattern for arXiv IDs: YYMM.NNNNN or category/YYMMNNN
    final patterns = [
      RegExp(r'arxiv\.org/abs/([a-z\-]+/\d+|\d+\.\d+)'),
      RegExp(r'arxiv\.org/pdf/([a-z\-]+/\d+|\d+\.\d+)'),
      RegExp(r'arxiv:([a-z\-]+/\d+|\d+\.\d+)'),
      RegExp(r'^(\d{4}\.\d{4,5})$'),
      RegExp(r'^([a-z\-]+/\d{7})$'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(input.toLowerCase());
      if (match != null) {
        return match.group(1);
      }
    }

    return null;
  }

  /// Check if input looks like an arXiv URL or ID
  static bool isArxivUrl(String input) {
    return parseArxivId(input) != null;
  }

  /// Fetch paper metadata from arXiv API
  Future<ArxivMetadata?> fetchMetadata(String arxivId) async {
    try {
      final url = Uri.parse('$_baseApiUrl?id_list=$arxivId');
      final response = await http.get(url);

      if (response.statusCode != 200) {
        print('arXiv API error: ${response.statusCode}');
        return null;
      }

      final document = XmlDocument.parse(response.body);
      final entries = document.findAllElements('entry');

      if (entries.isEmpty) {
        print('No entry found for arXiv ID: $arxivId');
        return null;
      }

      final entry = entries.first;

      // Extract metadata
      final title = _getElementText(
        entry,
        'title',
      )?.replaceAll('\n', ' ').trim();
      final summary = _getElementText(
        entry,
        'summary',
      )?.replaceAll('\n', ' ').trim();

      // Get authors
      final authors = entry
          .findAllElements('author')
          .map((a) => _getElementText(a, 'name'))
          .where((n) => n != null)
          .cast<String>()
          .join(', ');

      // Get category
      final primaryCategory = entry
          .findAllElements('arxiv:primary_category')
          .firstOrNull;
      final category = primaryCategory?.getAttribute('term');

      // Get PDF link
      final links = entry.findAllElements('link');
      String? pdfUrl;
      for (final link in links) {
        if (link.getAttribute('title') == 'pdf') {
          pdfUrl = link.getAttribute('href');
          break;
        }
      }
      pdfUrl ??= '$_pdfBaseUrl$arxivId.pdf';

      if (title == null || title.isEmpty) {
        return null;
      }

      return ArxivMetadata(
        arxivId: arxivId,
        title: title,
        authors: authors,
        abstract: summary ?? '',
        pdfUrl: pdfUrl,
        category: category,
      );
    } catch (e) {
      print('Error fetching arXiv metadata: $e');
      return null;
    }
  }

  String? _getElementText(XmlElement parent, String elementName) {
    final elements = parent.findElements(elementName);
    if (elements.isEmpty) return null;
    return elements.first.innerText;
  }

  /// Download PDF from arXiv
  Future<String?> downloadPdf(String arxivId) async {
    try {
      final pdfUrl = '$_pdfBaseUrl$arxivId.pdf';
      final response = await http.get(Uri.parse(pdfUrl));

      if (response.statusCode != 200) {
        print('Failed to download PDF: ${response.statusCode}');
        return null;
      }

      // Save to temp directory first
      final tempDir = await getTemporaryDirectory();
      final tempPath = p.join(tempDir.path, '$arxivId.pdf');

      final file = File(tempPath);
      await file.writeAsBytes(response.bodyBytes);

      return tempPath;
    } catch (e) {
      print('Error downloading arXiv PDF: $e');
      return null;
    }
  }
}
