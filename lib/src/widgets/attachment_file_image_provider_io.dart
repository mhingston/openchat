import 'dart:io';

import 'package:flutter/widgets.dart';

ImageProvider<Object> attachmentFileImageProvider(String path) {
  return FileImage(File(path));
}
