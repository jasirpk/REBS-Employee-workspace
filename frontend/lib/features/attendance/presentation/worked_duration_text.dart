import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/working_duration.dart';

// Shows "Worked: 2h 35m". While checked in it refreshes every minute; after
// checkout, or before check-in, no timer runs.
class WorkedDurationText extends StatefulWidget {
  final DateTime? checkIn;
  final DateTime? checkOut;
  // Injectable so tests can control the current time.
  final DateTime Function() clock;

  const WorkedDurationText({super.key, required this.checkIn, required this.checkOut, this.clock = DateTime.now});

  @override
  State<WorkedDurationText> createState() => _WorkedDurationTextState();
}

class _WorkedDurationTextState extends State<WorkedDurationText> {
  Timer? _timer;

  bool get _isRunning => widget.checkIn != null && widget.checkOut == null;

  @override
  void initState() {
    super.initState();
    _updateTimer();
  }

  @override
  void didUpdateWidget(WorkedDurationText oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateTimer();
  }

  // Starts one timer while checked in and stops it otherwise, so rebuilds
  // never create a second timer.
  void _updateTimer() {
    if (_isRunning) {
      _timer ??= Timer.periodic(const Duration(minutes: 1), (_) => setState(() {}));
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final duration = workedDuration(checkIn: widget.checkIn, checkOut: widget.checkOut, now: widget.clock());
    if (duration == null) return const SizedBox.shrink();

    return Text('Worked: ${formatWorkedDuration(duration)}');
  }
}
