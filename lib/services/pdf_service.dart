import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf_render/pdf_render.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as syncfusion;

/// Service for PDF file operations
class PdfService {
  static String? _storageDir;

  /// Get the PDF storage directory
  static Future<String> get storageDirectory async {
    if (_storageDir != null) return _storageDir!;

    final appDir = await getApplicationSupportDirectory();
    _storageDir = p.join(appDir.path, 'papers');
    await Directory(_storageDir!).create(recursive: true);
    return _storageDir!;
  }

  /// Copy PDF to app storage and return new path
  Future<String> importPdf(String sourcePath) async {
    final file = File(sourcePath);
    if (!await file.exists()) {
      throw Exception('PDF file not found: $sourcePath');
    }

    final storageDir = await PdfService.storageDirectory;
    final fileName = p.basename(sourcePath);

    // Generate unique filename if exists
    var destPath = p.join(storageDir, fileName);
    var counter = 1;
    while (await File(destPath).exists()) {
      final nameWithoutExt = p.basenameWithoutExtension(fileName);
      destPath = p.join(storageDir, '${nameWithoutExt}_$counter.pdf');
      counter++;
    }

    await file.copy(destPath);
    return destPath;
  }

  /// Extract text from PDF
  Future<String> extractText(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return '';
      }

      final bytes = await file.readAsBytes();
      final document = syncfusion.PdfDocument(inputBytes: bytes);

      final StringBuffer text = StringBuffer();
      for (int i = 0; i < document.pages.count; i++) {
        final pageText = syncfusion.PdfTextExtractor(
          document,
        ).extractText(startPageIndex: i, endPageIndex: i);
        text.writeln(pageText);
      }

      document.dispose();
      return text.toString();
    } catch (e) {
      print('Error extracting text from PDF: $e');
      return '';
    }
  }

  /// Extract title from PDF (uses metadata or first line of text)
  Future<String> extractTitle(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return p.basenameWithoutExtension(filePath);
      }

      final bytes = await file.readAsBytes();
      final document = syncfusion.PdfDocument(inputBytes: bytes);

      // Try PDF metadata title first
      final info = document.documentInformation;
      if (info.title.isNotEmpty) {
        document.dispose();
        return info.title;
      }

      // Try extracting from first page
      if (document.pages.count > 0) {
        final firstPageText = syncfusion.PdfTextExtractor(
          document,
        ).extractText(startPageIndex: 0, endPageIndex: 0);

        // Get first non-empty line as title
        final lines = firstPageText
            .split('\n')
            .where((l) => l.trim().isNotEmpty);
        if (lines.isNotEmpty) {
          var title = lines.first.trim();
          // Limit length
          if (title.length > 200) {
            title = title.substring(0, 200);
          }
          document.dispose();
          return title;
        }
      }

      document.dispose();
      return p.basenameWithoutExtension(filePath);
    } catch (e) {
      print('Error extracting title from PDF: $e');
      return p.basenameWithoutExtension(filePath);
    }
  }

  /// Delete PDF from storage
  Future<void> deletePdf(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Check if file is a valid PDF
  static bool isPdf(String path) {
    return path.toLowerCase().endsWith('.pdf');
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

  /// Get the thumbnail storage directory
  static Future<String> get thumbnailDirectory async {
    final appDir = await getApplicationSupportDirectory();
    final dir = Directory(p.join(appDir.path, 'thumbnails'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir.path;
  }

  /// Generate thumbnail for a PDF (first page)
  /// Returns path to the generated image file
  static Future<String?> generateThumbnail(String pdfPath, int paperId) async {
    try {
      final thumbDir = await thumbnailDirectory;
      final thumbPath = p.join(thumbDir, '$paperId.png');
      final thumbFile = File(thumbPath);

      if (await thumbFile.exists()) {
        return thumbPath;
      }

      final document = await PdfDocument.openFile(pdfPath);
      final page = await document.getPage(1); // 1-indexed

      // Calculate dimensions maintaining aspect ratio with width 300
      final width = 300;
      final height = (width * page.height / page.width).toInt();

      final pageImage = await page.render(width: width, height: height);

      // Create image from pixels
      final image = img.Image.fromBytes(
        width: pageImage.width,
        height: pageImage.height,
        bytes: pageImage.pixels.buffer,
        order: img.ChannelOrder.rgba,
        numChannels: 4,
      );

      // Encode to PNG
      final pngBytes = img.encodePng(image);
      await thumbFile.writeAsBytes(pngBytes);

      await document.dispose();

      return thumbPath;
    } catch (e) {
      print('Error generating thumbnail: $e');
      return null;
    }
  }

  /// Delete thumbnail
  static Future<void> deleteThumbnail(int paperId) async {
    try {
      final thumbDir = await thumbnailDirectory;
      final thumbPath = p.join(thumbDir, '$paperId.png');
      final thumbFile = File(thumbPath);
      if (await thumbFile.exists()) {
        await thumbFile.delete();
      }
    } catch (e) {
      print('Error deleting thumbnail: $e');
    }
  }
}
