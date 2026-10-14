import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

Widget webFrame(BuildContext context, Widget? child) {
  if (!kIsWeb) return child!; // mobile apps: untouched
  final mq = MediaQuery.of(context);
  final w = mq.size.width > 480 ? 480.0 : mq.size.width;
  return Container(
    color: const Color(0xFFEDE7DF),
    alignment: Alignment.topCenter,
    child: SizedBox(
      width: w,
      child: MediaQuery(
        data: mq.copyWith(size: Size(w, mq.size.height)),
        child: child!,
      ),
    ),
  );
}