import 'package:flutter/material.dart';

/// Whether [start] is genuinely before [end]. [TimeOfDay] carries no
/// ordering of its own, and a range absence that ends when it starts is
/// scored as zero minutes — both places that record one refuse it rather
/// than report an absence that credits nothing.
bool isAbsenceRangeInOrder(TimeOfDay start, TimeOfDay end) =>
    start.hour * 60 + start.minute < end.hour * 60 + end.minute;
