import 'package:flutter/painting.dart';
import 'package:intl/intl.dart' show Bidi;

/// A title is laid out in the direction of its own text: a Latin title in a Hebrew screen reads left to right (ellipsis at the end,
/// not at the front), a Hebrew title in an English screen reads right to left.
TextDirection titleDirection(String text) => Bidi.detectRtlDirectionality(text) ? TextDirection.rtl : TextDirection.ltr;
