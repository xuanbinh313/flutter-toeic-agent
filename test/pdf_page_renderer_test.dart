import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dictation_application/features/import_questions/pdf_page_renderer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_pdfviewer_platform_interface/pdfviewer_platform_interface.dart';

class _Renderer extends PdfViewerPlatform {
  int? requestedPage;
  bool closed = false;
  bool invalidPixels = false;

  @override
  Future<String?> initializePdfRenderer(
    Uint8List bytes,
    String documentId, [
    String? password,
  ]) async => '2';

  @override
  Future<List?> getPagesWidth(String documentId) async => [36, 18];

  @override
  Future<List?> getPagesHeight(String documentId) async => [36, 36];

  @override
  Future<Uint8List?> getPage(int page, int width, int height, String id) async {
    requestedPage = page;
    if (invalidPixels) return null;
    final pixels = Uint8List(width * height * 4);
    for (var i = 0; i < pixels.length; i += 4) {
      pixels[i] = 255;
      pixels[i + 3] = 255;
    }
    return pixels;
  }

  @override
  Future<void> closeDocument(String documentId) async => closed = true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late String pdfPath;
  late String outputPath;
  late PdfViewerPlatform original;
  late _Renderer platform;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('pdf_renderer_test_');
    pdfPath = '${directory.path}/source.pdf';
    outputPath = '${directory.path}/page.png';
    await File(pdfPath).writeAsBytes([37, 80, 68, 70]);
    original = PdfViewerPlatform.instance;
    platform = _Renderer();
    PdfViewerPlatform.instance = platform;
  });

  tearDown(() async {
    PdfViewerPlatform.instance = original;
    await directory.delete(recursive: true);
  });

  test(
    'renders selected page to a correctly sized PNG and closes PDF',
    () async {
      await PdfPageRenderer().render(pdfPath, 1, outputPath);
      expect(platform.requestedPage, 2);
      expect(platform.closed, isTrue);
      final codec = await ui.instantiateImageCodec(
        await File(outputPath).readAsBytes(),
      );
      final frame = await codec.getNextFrame();
      try {
        expect(frame.image.width, 50);
        expect(frame.image.height, 100);
        final rgba = await frame.image.toByteData();
        expect(rgba!.buffer.asUint8List().take(4), [255, 0, 0, 255]);
      } finally {
        frame.image.dispose();
        codec.dispose();
      }
    },
  );

  test('reports failed rendering and closes PDF without writing PNG', () async {
    platform.invalidPixels = true;
    await expectLater(
      PdfPageRenderer().render(pdfPath, 0, outputPath),
      throwsA(isA<StateError>()),
    );
    expect(platform.closed, isTrue);
    expect(File(outputPath).existsSync(), isFalse);
  });

  test(
    'rejects invalid page selections before rendering and closes PDF',
    () async {
      await expectLater(
        PdfPageRenderer().render(pdfPath, 2, outputPath),
        throwsRangeError,
      );
      expect(platform.requestedPage, isNull);
      expect(platform.closed, isTrue);
    },
  );
}
