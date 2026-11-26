import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  final File file = File('assets/app_icon.png');
  if (!file.existsSync()) {
    print("Icon file not found!");
    return;
  }

  // Read the image
  final bytes = file.readAsBytesSync();
  final originalImage = img.decodeImage(bytes);

  if (originalImage == null) {
    print("Failed to decode image");
    return;
  }

  final width = originalImage.width;
  final height = originalImage.height;

  // Zoom factor: 20% zoom in means we crop out 10% from each side.
  // We can adjust this to crop out the white part. Let's try 15% zoom.
  final cropFactor = 0.12; // 15% from each side = 30% total reduction

  final cropX = (width * cropFactor).toInt();
  final cropY = (height * cropFactor).toInt();
  final cropWidth = (width * (1 - 2 * cropFactor)).toInt();
  final cropHeight = (height * (1 - 2 * cropFactor)).toInt();

  // Crop the image
  final croppedImage = img.copyCrop(
    originalImage,
    x: cropX,
    y: cropY,
    width: cropWidth,
    height: cropHeight,
  );

  // Resize it back to high resolution just in case
  final resizedImage = img.copyResize(croppedImage, width: 1024, height: 1024);

  // Save it
  file.writeAsBytesSync(img.encodePng(resizedImage));
  print("Image cropped and saved successfully!");
}
