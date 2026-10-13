
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:iconsax/iconsax.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';

class WeekCalendarWidget extends StatefulWidget {
  final String propertyId;
  final String ownerId;

  const WeekCalendarWidget({
    super.key,
    required this.propertyId,
    required this.ownerId,
  });

  @override
  State<WeekCalendarWidget> createState() => _WeekCalendarWidgetState();
}

class _WeekCalendarWidgetState extends State<WeekCalendarWidget> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  bool _isExpanded = false;
  Map<DateTime, List<CalendarEvent>> _events = {};

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _loadEvents();
  }

  @override
  void didUpdateWidget(covariant WeekCalendarWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.propertyId != oldWidget.propertyId) {
      _loadEvents();
    }
  }

  Future<void> _loadEvents() async {
    setState(() {
      _events = {};
    });

    try {
      final now = DateTime.now();
      final Map<DateTime, List<CalendarEvent>> events = {};

      
      final bookingsSnapshot = await FirebaseFirestore.instance
          .collection('bookings')
          .where('ownerId', isEqualTo: widget.ownerId)
          .where('propertyId', isEqualTo: widget.propertyId)
          .where('status', whereIn: ['pending', 'awaiting_payment'])
          .get();

      for (var doc in bookingsSnapshot.docs) {
        final data = doc.data();
        final createdAt = (data['createdAt'] as Timestamp).toDate();
        final date = DateTime(createdAt.year, createdAt.month, createdAt.day);

        events.putIfAbsent(date, () => []);
        events[date]!.add(
          CalendarEvent(
            title: 'Booking Request',
            color: Colors.white,
            icon: Icons.pending_actions,
          ),
        );
      }

      
      final moveInsSnapshot = await FirebaseFirestore.instance
          .collection('bookings')
          .where('ownerId', isEqualTo: widget.ownerId)
          .where('propertyId', isEqualTo: widget.propertyId)
          .where('status', isEqualTo: 'booked')
          .get();

      for (var doc in moveInsSnapshot.docs) {
        final data = doc.data();
        if (data['bookingDate'] != null) {
          final moveInDate = (data['bookingDate'] as Timestamp).toDate();
          final date = DateTime(
            moveInDate.year,
            moveInDate.month,
            moveInDate.day,
          );

          events.putIfAbsent(date, () => []);
          events[date]!.add(
            CalendarEvent(
              title: 'Move-in: ${data['roomName']}',
              color: Colors.blue,
              icon: Iconsax.login,
            ),
          );
        }
      }

      
      final firstOfMonth = DateTime(now.year, now.month, 1);
      events.putIfAbsent(firstOfMonth, () => []);
      events[firstOfMonth]!.add(
        CalendarEvent(
          title: 'Rent Due',
          color: Colors.orange,
          icon: Iconsax.card,
        ),
      );

      
      final propertyDoc = await FirebaseFirestore.instance
          .collection('properties')
          .doc(widget.propertyId)
          .get();

      if (propertyDoc.exists) {
        final data = propertyDoc.data()!;
        if (data['verificationSchedule'] != null) {
          final verificationDate = (data['verificationSchedule'] as Timestamp)
              .toDate();
          final date = DateTime(
            verificationDate.year,
            verificationDate.month,
            verificationDate.day,
          );

          events.putIfAbsent(date, () => []);
          events[date]!.add(
            CalendarEvent(
              title: 'Property Verification',
              color: const Color.fromARGB(255, 125, 241, 133),
              icon: Icons.verified,
            ),
          );
        }
      }

      
      final roomVerifySnapshot = await FirebaseFirestore.instance
          .collection('properties')
          .doc(widget.propertyId)
          .collection('rooms')
          .where('verificationStatus', whereIn: ['pending', 'reverify'])
          .get();

      for (var doc in roomVerifySnapshot.docs) {
        final data = doc.data();
        if (data['verificationSchedule'] != null) {
          final verificationDate = (data['verificationSchedule'] as Timestamp)
              .toDate();
          final date = DateTime(
            verificationDate.year,
            verificationDate.month,
            verificationDate.day,
          );

          final roomName = data['name'] ?? 'Unknown Room';

          events.putIfAbsent(date, () => []);
          events[date]!.add(
            CalendarEvent(
              title: 'Verify: $roomName',
              color: const Color.fromARGB(255, 132, 250, 136),
              icon: Icons.meeting_room,
            ),
          );
        }
      }

      if (mounted) {
        setState(() {
          _events = events;
        });
      }
    } catch (e) {
      debugPrint('Error loading events: $e');
    }
  }

  List<CalendarEvent> _getEventsForDay(DateTime day) {
    final key = DateTime(day.year, day.month, day.day);
    return _events[key] ?? [];
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const RadialGradient(
            center: Alignment.topLeft,
            radius: 1.2,
            colors: [
               Color.fromARGB(255, 103, 194, 237),
              Color.fromARGB(255, 22, 104, 197),
              Color.fromARGB(255, 11, 63, 142),
            ],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(15, 5, 15, 5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Iconsax.calendar, color: Colors.white),
                      SizedBox(width: 8),
                      Text(
                        'Schedule',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: Icon(
                      _isExpanded ? Iconsax.arrow_square_up : Iconsax.arrow_square_down,
                      color: Colors.white,
                    ),
                    onPressed: () {
                      setState(() {
                        _isExpanded = !_isExpanded;
                      });
                    },
                  ),
                ],
              ),

              

              
              TableCalendar(
                firstDay: DateTime.utc(2020, 1, 1),
                lastDay: DateTime.utc(2030, 12, 31),
                focusedDay: _focusedDay,
                selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                calendarFormat: _isExpanded
                    ? CalendarFormat.month
                    : CalendarFormat.week,
                eventLoader: _getEventsForDay,
                onDaySelected: (selectedDay, focusedDay) {
                  if (!isSameDay(_selectedDay, selectedDay)) {
                    setState(() {
                      _selectedDay = selectedDay;
                      _focusedDay = focusedDay;
                    });
                  }
                },
                onPageChanged: (focusedDay) {
                  _focusedDay = focusedDay;
                },
                calendarStyle: CalendarStyle(
                  todayDecoration: BoxDecoration(
                    color: Colors.white.withAlpha(50),
                    shape: BoxShape.circle,
                  ),
                  defaultTextStyle: const TextStyle(color: Colors.white),
                  weekendTextStyle: const TextStyle(color: Colors.white),
                  outsideTextStyle: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                  ),
                  todayTextStyle: const TextStyle(color: Colors.white),
                  selectedTextStyle: const TextStyle(color: Colors.white),
                  selectedDecoration: const BoxDecoration(
                    color: Color.fromARGB(108, 255, 255, 255),
                    shape: BoxShape.circle,
                  ),
                  
                  markersMaxCount: 4,
                ),
                headerStyle: HeaderStyle(
                  formatButtonVisible: false,
                  titleCentered: true,
                  titleTextFormatter: (date, locale) =>
                      DateFormat.yMMMM(locale).format(date),
                  leftChevronIcon: const Icon(
                    Iconsax.arrow_circle_left,
                    color: Colors.white,
                  ),
                  rightChevronIcon: const Icon(
                    Iconsax.arrow_circle_right,
                    color: Colors.white,
                  ),
                  titleTextStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                daysOfWeekStyle: const DaysOfWeekStyle(
                  weekdayStyle: TextStyle(color: Colors.white70),
                  weekendStyle: TextStyle(color: Colors.white70),
                ),
                
                calendarBuilders: CalendarBuilders(
                  markerBuilder: (context, day, events) {
                    if (events.isEmpty) return const SizedBox();
                    return ListView.builder(
                      shrinkWrap: true,
                      scrollDirection: Axis.horizontal,
                      itemCount: events.length,
                      itemBuilder: (context, index) {
                        final event = events[index] as CalendarEvent;
                        return Container(
                          margin: const EdgeInsets.only(top: 20, right: 2),
                          padding: const EdgeInsets.all(1),
                          height: 7,
                          width: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: event.color,
                          ),
                        );
                      },
                    );
                  },
                ),
              ),

              const SizedBox(height: 16),

              
              if (_selectedDay != null) ...[
                const Divider(),
                const SizedBox(height: 8),
                Text(
                  'Events on ${DateFormat('MMMM d, yyyy').format(_selectedDay!)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 12),
                _buildEventsList(_getEventsForDay(_selectedDay!)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEventsList(List<CalendarEvent> events) {
    if (events.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text(
            'No events scheduled',
            style: TextStyle(color: Colors.white, fontSize: 14),
          ),
        ),
      );
    }

    return Column(
      children: events.map((event) {
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: event.color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: event.color.withOpacity(0.3), width: 1),
          ),
          child: Row(
            children: [
              Icon(event.icon, color: event.color, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  event.title,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class CalendarEvent {
  final String title;
  final Color color;
  final IconData icon;

  CalendarEvent({required this.title, required this.color, required this.icon});
}
