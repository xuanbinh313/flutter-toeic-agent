import 'dart:io';

import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class PartOneImageSplitter {
  Future<List<String>> splitPdfPages(
    String pdfPath,
    List<int> pageIndices,
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
    final images = <String>[];
    for (final pageIndex in pageIndices.toSet().toList()..sort()) {
      final pageImage = await _renderPdfPage(pdfPath, pageIndex, output);
      final split = _splitImage(pageImage, output);
      if (split.length != 2) {
        throw StateError(
          'Part 1 page ${pageIndex + 1} must contain exactly two photographs.',
        );
      }
      images.addAll(split);
    }
    return images;
  }

  Future<String> _renderPdfPage(
    String pdfPath,
    int pageIndex,
    Directory output,
  ) async {
    final prefix = path.join(output.path, 'page_${pageIndex + 1}');
    ProcessResult result;
    try {
      result = await Process.run('pdftoppm', [
        '-f',
        '${pageIndex + 1}',
        '-l',
        '${pageIndex + 1}',
        '-r',
        '200',
        '-png',
        '-singlefile',
        pdfPath,
        prefix,
      ]);
    } on ProcessException catch (error) {
      throw StateError('PDF page rendering is unavailable: $error');
    }
    final imagePath = '$prefix.png';
    if (result.exitCode != 0 || !File(imagePath).existsSync()) {
      throw StateError(
        'Could not render Part 1 page ${pageIndex + 1}: ${result.stderr}',
      );
    }
    return imagePath;
  }

  List<String> _splitImage(String imagePath, Directory output) {
    final image = cv.imread(imagePath);
    if (image.isEmpty) {
      image.dispose();
      throw StateError('Could not read ${path.basename(imagePath)}.');
    }
    cv.Mat? gray;
    cv.Mat? blur;
    cv.Mat? binary;
    cv.Mat? closed;
    cv.Mat? dilated;
    cv.Mat? kernel;
    cv.Contours? contours;
    cv.VecVec4i? hierarchy;
    try {
      gray = cv.cvtColor(image, cv.COLOR_BGR2GRAY);
      blur = cv.gaussianBlur(gray, (5, 5), 0);
      binary = cv
          .threshold(blur, 0, 255, cv.THRESH_BINARY_INV | cv.THRESH_OTSU)
          .$2;
      kernel = cv.getStructuringElement(cv.MORPH_RECT, (20, 20));
      closed = cv.morphologyEx(binary, cv.MORPH_CLOSE, kernel);
      dilated = cv.dilate(closed, kernel);

      final marginX = (image.cols * 0.05).round();
      final marginY = (image.rows * 0.05).round();
      _clearMargin(dilated, marginX, marginY);
      final result = cv.findContours(
        dilated,
        cv.RETR_EXTERNAL,
        cv.CHAIN_APPROX_SIMPLE,
      );
      contours = result.$1;
      hierarchy = result.$2;
      final boxes = <cv.Rect>[];
      for (final contour in contours) {
        final box = cv.boundingRect(contour);
        final largeEnough =
            box.width > image.cols * 0.25 && box.height > image.rows * 0.15;
        final notFullPage =
            box.width < image.cols * 0.98 && box.height < image.rows * 0.98;
        if (largeEnough && notFullPage) {
          boxes.add(box);
        } else {
          box.dispose();
        }
      }
      boxes.sort((a, b) => (b.width * b.height).compareTo(a.width * a.height));
      if (boxes.length < 2) {
        for (final box in boxes) {
          box.dispose();
        }
        return [];
      }
      final selected = boxes.take(2).toList()
        ..sort((a, b) => a.y.compareTo(b.y));
      for (final box in boxes.skip(2)) {
        box.dispose();
      }
      final paths = <String>[];
      for (var index = 0; index < selected.length; index++) {
        final crop = cv.Mat.fromMat(image, roi: selected[index], copy: true);
        final outputPath = path.join(
          output.path,
          '${path.basenameWithoutExtension(imagePath)}_part_${index + 1}.png',
        );
        try {
          if (!cv.imwrite(outputPath, crop)) {
            throw StateError('Could not save ${path.basename(outputPath)}.');
          }
          paths.add(outputPath);
        } finally {
          crop.dispose();
          selected[index].dispose();
        }
      }
      return paths;
    } finally {
      hierarchy?.dispose();
      contours?.dispose();
      kernel?.dispose();
      dilated?.dispose();
      closed?.dispose();
      binary?.dispose();
      blur?.dispose();
      gray?.dispose();
      image.dispose();
    }
  }

  void _clearMargin(cv.Mat image, int marginX, int marginY) {
    final top = cv.Mat.fromRange(image, 0, marginY, colEnd: image.cols);
    final bottom = cv.Mat.fromRange(
      image,
      image.rows - marginY,
      image.rows,
      colEnd: image.cols,
    );
    final left = cv.Mat.fromRange(image, 0, image.rows, colEnd: marginX);
    final right = cv.Mat.fromRange(
      image,
      0,
      image.rows,
      colStart: image.cols - marginX,
    );
    try {
      top.setTo(cv.Scalar.all(0));
      bottom.setTo(cv.Scalar.all(0));
      left.setTo(cv.Scalar.all(0));
      right.setTo(cv.Scalar.all(0));
    } finally {
      top.dispose();
      bottom.dispose();
      left.dispose();
      right.dispose();
    }
  }
}
