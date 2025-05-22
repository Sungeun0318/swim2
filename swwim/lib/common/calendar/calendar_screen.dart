import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'widgets/DailyAnalysisScreen.dart';
import 'widgets/training_item.dart';
import 'dialogs/dialog_training_input.dart';
import 'dialogs/dialog_delete.dart';
import 'dialogs/dialog_share.dart';
import 'dialogs/dialog_preschedule.dart';
import 'widgets/fab_menu.dart';
import 'widgets/monthly_analysis_screen.dart'; // ← 추가
import 'widgets/swim_record.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  bool _fabExpanded = false;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  final Map<DateTime, List<TrainingItem>> _events = {};

  // 더미 수영 기록 데이터
  final List<SwimRecord> demoRecords = [
    SwimRecord(date: DateTime(2025, 5, 3), distance: 1050, duration: Duration(hours: 1, minutes: 39)),
    SwimRecord(date: DateTime(2025, 5, 6), distance: 700, duration: Duration(hours: 1)),
    SwimRecord(date: DateTime(2025, 5, 8), distance: 750, duration: Duration(hours: 1, minutes: 5)),
    SwimRecord(date: DateTime(2025, 5, 10), distance: 1000, duration: Duration(hours: 1, minutes: 20)),
    SwimRecord(date: DateTime(2025, 5, 14), distance: 300, duration: Duration(minutes: 30)),
    SwimRecord(date: DateTime(2025, 5, 18), distance: 1200, duration: Duration(minutes: 30)),
  ];

  // 이번 달 기록 필터
  List<SwimRecord> get _thisMonthRecords => demoRecords
      .where((r) => r.date.year == _focusedDay.year && r.date.month == _focusedDay.month)
      .toList();

  // 통계
  double get _totalDistanceKm {
    final meters = _thisMonthRecords.fold<double>(0, (sum, r) => sum + r.distance);
    return meters / 1000;
  }
  int get _totalSessions => _thisMonthRecords.length;
  Duration get _totalDuration => _thisMonthRecords.fold<Duration>(Duration.zero, (sum, r) => sum + r.duration);
  String get _totalDurationStr {
    final h = _totalDuration.inHours;
    final m = _totalDuration.inMinutes % 60;
    return '${h}h ${m}m';
  }

  // 다이얼로그에서 넘어온 훈련 기록 추가
  void _addTraining(TrainingItem item) {
    final key = DateTime.utc(item.date.year, item.date.month, item.date.day);
    setState(() {
      _events[key] ??= [];
      _events[key]!.add(item);
    });
  }

  List<TrainingItem> _getEvents(DateTime day) {
    final key = DateTime.utc(day.year, day.month, day.day);

    final trainings = _events[key] ?? [];

    //    TrainingItem으로 변환하기
    final swims = demoRecords
        .where((r) => isSameDay(r.date, day))
        .map((r) => TrainingItem(
      date: r.date,
      name: '수영 ${r.distance}m',
      distance: r.distance.toString(),
      time: '${r.duration.inHours}h ${r.duration.inMinutes % 60}m',
    ))
        .toList();

    return [...trainings, ...swims];
  }

  @override
  Widget build(BuildContext context) {
    final monthLabel = DateFormat('yyyy년 M월').format(_focusedDay);

    return Scaffold(
      appBar: AppBar(
        title: const Text('기록', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.schedule),
          onPressed: () => showPreScheduleDialog(context),
        ),
        actions: [

          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () => showShareDialog(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // 월 이동 + 오늘 버튼
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: _prevMonth,
                ),
                Text(monthLabel, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _nextMonth,
                ),
                const Spacer(),
                TextButton(
                  onPressed: _goToday,
                  child: const Text('오늘', style: TextStyle(color: Colors.blue)),
                ),
              ],
            ),
          ),

          // 월별 요약 카드
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 2,
              child: InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => MonthlyAnalysisScreen(
                        focusedMonth: _focusedDay,
                        allRecords: demoRecords,
                      ),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.bar_chart_outlined, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                '${DateFormat('M월').format(_focusedDay)} 용범님의 수영 분석',
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.bold
                                ),
                              ),
                            ],
                          ),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _StatColumn(label: '총 수영 거리', value: '${_totalDistanceKm.toStringAsFixed(1)}km'),
                          _StatColumn(label: '총 수영 횟수', value: '$_totalSessions회'),
                          _StatColumn(label: '총 수영 시간', value: _totalDurationStr),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 캘린더
          TableCalendar(
            headerVisible: false,
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2030, 12, 31),
            focusedDay: _focusedDay,
            selectedDayPredicate: (d) => isSameDay(_selectedDay, d),
            calendarFormat: CalendarFormat.month,
            eventLoader: _getEvents,
            daysOfWeekStyle: DaysOfWeekStyle(
              dowTextFormatter: (date, locale) => DateFormat.E(locale).format(date),
              weekendStyle: const TextStyle(color: Colors.blue),
              weekdayStyle: const TextStyle(color: Colors.grey),
            ),
            calendarStyle: const CalendarStyle(outsideDaysVisible: false,markersMaxCount: 0,),
            availableGestures: AvailableGestures.horizontalSwipe,
            onPageChanged: (focused) => setState(() { _focusedDay = focused; }),
            calendarBuilders: CalendarBuilders(
              defaultBuilder: (ctx, day, _) => _buildDayCell(day),
              todayBuilder: (ctx, day, _) => _buildDayCell(day, isToday: true),
              selectedBuilder: (ctx, day, _) => _buildDayCell(day, isSelected: true),
            ),

            onDaySelected: (selectedDay, focusedDay) {
              // 1) 상태 업데이트
              setState(() {
                _selectedDay = selectedDay;
                _focusedDay = focusedDay;
              });
              // 2) 동일 날짜의 SwimRecord 찾기
              final recordsOnDay = demoRecords.where(
                      (r) => isSameDay(r.date, selectedDay));
              // 3) 있으면 DailyAnalysisScreen으로 이동
              if (recordsOnDay.isNotEmpty) {
                final record = recordsOnDay.first;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DailyAnalysisScreen(record: record),
                  ),
                );
              }
            },
          ),

          // 선택일 이벤트 리스트
          Expanded(
            child: ListView.separated(
              itemCount: _getEvents(_selectedDay ?? _focusedDay).length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (ctx, idx) {
                final item = _getEvents(_selectedDay ?? _focusedDay)[idx];
                return ListTile(
                  title: Text(item.name),
                  subtitle: Text('${item.distance} • ${item.time}'),
                  onLongPress: () => _deleteItem(item),
                );
              },
            ),
          ),
        ],
      ),

      // FAB 메뉴
      floatingActionButton: FabMenu(
        isExpanded: _fabExpanded,
        toggle: () => setState(() => _fabExpanded = !_fabExpanded),
        onAction: _onFabAction,
      ),
    );
  }

  void _prevMonth() => setState(() {
    _focusedDay = DateTime(_focusedDay.year, _focusedDay.month - 1, 1);
  });

  void _nextMonth() => setState(() {
    _focusedDay = DateTime(_focusedDay.year, _focusedDay.month + 1, 1);
  });

  void _goToday() => setState(() {
    _focusedDay = DateTime.now();
    _selectedDay = DateTime.now();
  });

  Future<void> _showWeekGraph() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      initialDateRange: DateTimeRange(
        start: DateTime.now().subtract(const Duration(days: 7)),
        end: DateTime.now(),
      ),
    );
    /*if (range != null) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('운동량 그래프'),
          content: SizedBox(
            height: 200,
            width: double.maxFinite,
            child: ExerciseGraphWidget(dateRange: range, events: _events),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('닫기'))
          ],
        ),
      );
    }*/
  }

  void _onFabAction(String label) {
    setState(() => _fabExpanded = false);
    final dateToAdd = _selectedDay ?? _focusedDay;
    switch (label) {
      case '훈련 추가':
        showTrainingInputDialog(context, dateToAdd, _addTraining);
        break;
      case '캘린더 공유':
        showShareDialog(context);
        break;
      case '리스트 삭제':
        final list = List<TrainingItem>.from(_getEvents(dateToAdd));
        showDeleteDialog(context, list, (toDelete) {
          setState(() {
            final key = DateTime.utc(dateToAdd.year, dateToAdd.month, dateToAdd.day);
            _events[key]?.removeWhere((e) => toDelete.contains(e));
            if (_events[key]?.isEmpty ?? false) _events.remove(key);
          });
        });
        break;
      case '미리 일정':
        showPreScheduleDialog(context);
        break;
    }
  }

  void _deleteItem(TrainingItem item) {
    final dayKey = _selectedDay ?? _focusedDay;
    final list = List<TrainingItem>.from(_getEvents(dayKey));
    showDeleteDialog(context, list, (toDelete) {
      setState(() {
        final key = DateTime.utc(dayKey.year, dayKey.month, dayKey.day);
        _events[key]?.removeWhere((e) => toDelete.contains(e));
        if (_events[key]?.isEmpty ?? false) _events.remove(key);
      });
    });
  }

  Widget _buildDayCell(DateTime day, {bool isToday = false, bool isSelected = false}) {
    final events = _getEvents(day);
    return Container(
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isSelected
            ? Colors.blue.shade100
            : isToday
            ? Colors.blue.shade50
            : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Stack(
        children: [
          Center(child: Text('${day.day}', style: TextStyle(color: isSelected ? Colors.blue : Colors.black))),
          if (events.isNotEmpty)
            Positioned(
              bottom: 4,
              left: 4,
              right: 4,
              child: Row(
                children: events.map((_) => Expanded(child: Container(height: 4, color: Colors.green))).toList(),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  final String label;
  final String value;
  const _StatColumn({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
