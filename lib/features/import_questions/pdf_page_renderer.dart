import 'dart:io';
import 'dart:ui' as ui;

import 'package:syncfusion_pdfviewer_platform_interface/pdfviewer_platform_interface.dart';

/// Uses the same bundled renderer as the PDF page selector, at 200 DPI.
class PdfPageRenderer {
  Future<void> render(String pdfPath, int pageIndex, String outputPath) async {
    final platform = PdfViewerPlatform.instance;
    final documentId = 'import_${DateTime.now().microsecondsSinceEpoch}';
    final result = await platform.initializePdfRenderer(
      await File(pdfPath).readAsBytes(),
      documentId,
    );
    final pageCount = int.tryParse(result ?? '');
    if (pageCount == null || pageCount <= 0) {
      throw StateError(
        'Could not open Part 1 PDF: ${result ?? 'no response'}.',
      );
    }
    try {
      if (pageIndex < 0 || pageIndex >= pageCount) {
        throw RangeError.range(pageIndex, 0, pageCount - 1, 'pageIndex');
      }
      final widths = await platform.getPagesWidth(documentId);
      final heights = await platform.getPagesHeight(documentId);
      if (widths == null ||
          heights == null ||
          widths.length <= pageIndex ||
          heights.length <= pageIndex) {
        throw StateError(
          'Missing dimensions for Part 1 page ${pageIndex + 1}.',
        );
      }
      final width = ((widths[pageIndex] as num) * 200 / 72).round();
      final height = ((heights[pageIndex] as num) * 200 / 72).round();
      if (width <= 0 || height <= 0) {
        throw StateError(
          'Invalid dimensions for Part 1 page ${pageIndex + 1}.',
        );
      }
      final pixels = await platform.getPage(
        pageIndex + 1,
        width,
        height,
        documentId,
      );
      if (pixels == null || pixels.length != width * height * 4) {
        throw StateError(
          'Could not render Part 1 page ${pageIndex + 1}: invalid pixel data.',
        );
      }
      final buffer = await ui.ImmutableBuffer.fromUint8List(pixels);
      final descriptor = ui.ImageDescriptor.raw(
        buffer,
        width: width,
        height: height,
        pixelFormat: ui.PixelFormat.rgba8888,
      );
      try {
        final codec = await descriptor.instantiateCodec();
        try {
          final frame = await codec.getNextFrame();
          try {
            final png = await frame.image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            if (png == null) {
              throw StateError(
                'Could not encode Part 1 page ${pageIndex + 1}.',
              );
            }
            await File(outputPath).writeAsBytes(
              png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
              flush: true,
            );
          } finally {
            frame.image.dispose();
          }
        } finally {
          codec.dispose();
        }
      } finally {
        descriptor.dispose();
        buffer.dispose();
      }
    } finally {
      await platform.closeDocument(documentId);
    }
  }
}
