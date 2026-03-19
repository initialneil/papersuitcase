import 'dart:io';
import 'dart:isolate';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pdf_render/pdf_render.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as syncfusion;

/// Top-level function for Isolate.run — extracts title + text from PDF bytes.
/// Must be top-level (not a method) for isolate compatibility.
Map<String, String> _extractPdfDataSync(List<int> bytes) {
  String title = '';
  String text = '';

  try {
    final document = syncfusion.PdfDocument(inputBytes: bytes);

    // Extract title from metadata
    try {
      final info = document.documentInformation;
      // ignore: unnecessary_null_comparison
      if (info != null && info.title != null && info.title.isNotEmpty) {
        title = info.title;
      }
    } catch (_) {}

    // Fallback: first line of first page
    if (title.isEmpty && document.pages.count > 0) {
      try {
        final firstPageText = syncfusion.PdfTextExtractor(document)
            .extractText(startPageIndex: 0, endPageIndex: 0);
        final lines =
            firstPageText.split('\n').where((l) => l.trim().isNotEmpty);
        if (lines.isNotEmpty) {
          title = lines.first.trim();
          if (title.length > 200) title = title.substring(0, 200);
        }
      } catch (_) {}
    }

    // Extract full text (limit to first 20 pages for speed)
    try {
      final buf = StringBuffer();
      final maxPages =
          document.pages.count < 20 ? document.pages.count : 20;
      for (int i = 0; i < maxPages; i++) {
        buf.writeln(syncfusion.PdfTextExtractor(document)
            .extractText(startPageIndex: i, endPageIndex: i));
      }
      text = buf.toString();
    } catch (_) {}

    document.dispose();
  } catch (_) {}

  return {'title': title, 'text': text};
}

/// Service for PDF file operations
class PdfService {
  /// Extract title and text from PDF in a background isolate.
  /// Returns {'title': ..., 'text': ...}.
  /// This runs CPU-heavy Syncfusion parsing off the main thread.
  Future<Map<String, String>> extractInIsolate(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return {
          'title': p.basenameWithoutExtension(filePath),
          'text': ''
        };
      }

      final bytes = await file.readAsBytes();
      final result = await Isolate.run(() => _extractPdfDataSync(bytes));

      // If title is empty, fall back to filename
      if (result['title'] == null || result['title']!.isEmpty) {
        result['title'] = p.basenameWithoutExtension(filePath);
      }
      return result;
    } catch (e) {
      return {
        'title': p.basenameWithoutExtension(filePath),
        'text': ''
      };
    }
  }

  /// Extract text from PDF (legacy — runs on main isolate)
  Future<String> extractText(String filePath) async {
    final result = await extractInIsolate(filePath);
    return result['text'] ?? '';
  }

  /// Extract title from PDF (legacy — runs on main isolate)
  Future<String> extractTitle(String filePath) async {
    final result = await extractInIsolate(filePath);
    return result['title'] ?? p.basenameWithoutExtension(filePath);
  }

  /// Check if file is a valid PDF
  static bool isPdf(String path) {
    return path.toLowerCase().endsWith('.pdf');
  }

  /// Open PDF with custom application
  static Future<bool> openWithCustomApp(String filePath, String appPath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return false;
      }

      // Use open -a command on macOS for custom app
      final result = await Process.run('open', ['-a', appPath, filePath]);
      return result.exitCode == 0;
    } catch (e) {
      print('Error opening PDF with custom app: $e');
      return false;
    }
  }

  /// Open PDF with system default viewer
  static Future<bool> openWithSystemViewer(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return false;
      }

      // Use open command on macOS
      final result = await Process.run('open', [filePath]);
      return result.exitCode == 0;
    } catch (e) {
      print('Error opening PDF: $e');
      return false;
    }
  }

  /// Reveal file in Finder
  static Future<bool> revealInFinder(String filePath) async {
    try {
      final result = await Process.run('open', ['-R', filePath]);
      return result.exitCode == 0;
    } catch (e) {
      print('Error revealing file: $e');
      return false;
    }
  }

  /// Generate thumbnail for a PDF to a specific output path.
  /// Used by entry scanner to store thumbnails in .papersuitecase/thumbnails/.
  static Future<String?> generateThumbnailToPath(
      String pdfPath, String outputPath) async {
    try {
      final thumbFile = File(outputPath);
      if (await thumbFile.exists()) return outputPath;
      await Directory(p.dirname(outputPath)).create(recursive: true);

      PdfDocument document;
      try {
        document = await PdfDocument.openFile(pdfPath);
      } catch (e) {
        final bytes = await File(pdfPath).readAsBytes();
        document = await PdfDocument.openData(bytes);
      }

      final page = await document.getPage(1);
      final width = 300;
      final height = (width * page.height / page.width).toInt();
      final pageImage = await page.render(width: width, height: height);

      final image = img.Image.fromBytes(
        width: pageImage.width,
        height: pageImage.height,
        bytes: pageImage.pixels.buffer,
        order: img.ChannelOrder.rgba,
        numChannels: 4,
      );

      final pngBytes = img.encodePng(image);
      await thumbFile.writeAsBytes(pngBytes);
      await document.dispose();
      return outputPath;
    } catch (e) {
      print('Error generating thumbnail to path: $e');
      return null;
    }
  }

}
