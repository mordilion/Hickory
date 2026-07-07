String formatDuration(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  final seconds = d.inSeconds.remainder(60);
  final h = hours.toString().padLeft(2, '0');
  final m = minutes.toString().padLeft(2, '0');
  final s = seconds.toString().padLeft(2, '0');
  return '$h:$m:$s';
}
