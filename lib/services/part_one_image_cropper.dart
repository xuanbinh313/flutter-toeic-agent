import 'dart:io';
import 'dart:ui' as ui;

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../features/import_questions/pdf_page_renderer.dart';

class PartOneImageCropper {
  Future<List<String>> cropPdfRegions(
    String pdfPath,
    List<int> selectedPageIndices,
    List<Map<String, dynamic>> regions,
  ) async {
    final root = await getApplicationSupportDirectory();
    final output = Directory(
      path.join(
        root.path,
        'part_1_images',
        DateTime.now().microsecondsSinceEpoch.toString(),
      ),
    );
    await output.create(recursive: true);
    final pageImages = <int, ui.Image>{};
    final renderedPaths = <int, String>{};
    try {
      final ordered = List<Map<String, dynamic>>.from(regions)
        ..sort(
          (a, b) => (a['question_number'] as int).compareTo(
            b['question_number'] as int,
          ),
        );
      final result = <String>[];
      for (final region in ordered) {
        final pageOrdinal = region['page'] as int;
        if (pageOrdinal < 1 || pageOrdinal > selectedPageIndices.length) {
          throw FormatException(
            'Part 1 image region refers to invalid selected page $pageOrdinal.',
          );
        }
        final pageIndex = selectedPageIndices[pageOrdinal - 1];
        var page = pageImages[pageIndex];
        if (page == null) {
          final renderedPath = path.join(
            output.path,
            'page_${pageIndex + 1}.png',
          );
          await PdfPageRenderer().render(pdfPath, pageIndex, renderedPath);
          renderedPaths[pageIndex] = renderedPath;
          final bytes = await File(renderedPath).readAsBytes();
          final codec = await ui.instantiateImageCodec(bytes);
          try {
            page = (await codec.getNextFrame()).image;
          } finally {
            codec.dispose();
          }
          pageImages[pageIndex] = page;
        }
        final x = _coordinate(region, 'x');
        final y = _coordinate(region, 'y');
        final width = _coordinate(region, 'width');
        final height = _coordinate(region, 'height');
        if (width <= 0 ||
            height <= 0 ||
            x + width > 1.001 ||
            y + height > 1.001) {
          throw FormatException('Part 1 image region has invalid bounds.');
        }
        final left = (x * page.width).round().clamp(0, page.width - 1);
        final top = (y * page.height).round().clamp(0, page.height - 1);
        final right = ((x + width) * page.width).round().clamp(
          left + 1,
          page.width,
        );
        final bottom = ((y + height) * page.height).round().clamp(
          top + 1,
          page.height,
        );
        final cropWidth = right - left;
        final cropHeight = bottom - top;
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        canvas.drawImageRect(
          page,
          ui.Rect.fromLTWH(
            left.toDouble(),
            top.toDouble(),
            cropWidth.toDouble(),
            cropHeight.toDouble(),
          ),
          ui.Rect.fromLTWH(0, 0, cropWidth.toDouble(), cropHeight.toDouble()),
          ui.Paint(),
        );
        final cropped = await recorder.endRecording().toImage(
          cropWidth,
          cropHeight,
        );
        try {
          final data = await cropped.toByteData(format: ui.ImageByteFormat.png);
          if (data == null) {
            throw StateError('Could not encode cropped Part 1 photograph.');
          }
          final outputPath = path.join(
            output.path,
            'question_${region['question_number']}.png',
          );
          await File(outputPath).writeAsBytes(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
            flush: true,
          );
          result.add(outputPath);
        } finally {
          cropped.dispose();
        }
      }
      return result;
    } finally {
      for (final image in pageImages.values) {
        image.dispose();
      }
      for (final rendered in renderedPaths.values) {
        final file = File(rendered);
        if (await file.exists()) {
          await file.delete();
        }
      }
    }
  }

  double _coordinate(Map<String, dynamic> region, String key) {
    final value = region[key];
    if (value is! num || !value.isFinite || value < 0 || value > 1) {
      throw FormatException('Part 1 image region has invalid $key coordinate.');
    }
    return value.toDouble();
  }
}
