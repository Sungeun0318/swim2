import 'dart:async';
// import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../services/tg_sound_manager.dart';
import '../utils/tg_format_time.dart';
import 'package:swim/features/swimming/models/training_detail_data.dart';

class TGTimerController {
  final List<TrainingDetailData> trainingList;
  final String beepSound;
  final int numPeople;
  final VoidCallback onUpdate;
  final void Function(String action)? onEvent; // "start", "pause", "resume", "reset", "cycle_beep", "complete"

  Timer? _timer;
  Timer? _restTimer;
  Timer? _nextTrainingNotificationTimer;
  final List<Timer> _scheduledBeeps = [];

  DateTime? _startTime;
  Duration _pausedDuration = Duration.zero;
  DateTime? _pauseStart;
  DateTime? _stopTime;

  int _currentTrainingIndex = 0;
  int _currentCycleCount = 0;
  bool _isRunning = false;
  bool _isPaused = false;
  bool _isFinalCycle = false;
  bool _isResting = false;
  int _restTimeRemaining = 0;
  String _restMessage = "";
  bool _isCompleted = false;

  final SoundManager _soundManager = SoundManager();
  double? _lastTotalProgress; // 마지막으로 계산된 총 진행률
  double? _lastCurrentProgress; // 마지막으로 계산된 현재 진행률

  TGTimerController({
    required this.trainingList,
    required this.beepSound,
    required this.numPeople,
    required this.onUpdate,
    this.onEvent,
  });

  int get currentTrainingIndex => _currentTrainingIndex;
  int get currentCycleIndex => _currentCycleCount;
  int get currentCycleTime => trainingList[_currentTrainingIndex].cycle;
  bool get isFinalCycle => _isFinalCycle;
  bool get isResting => _isResting;
  bool get isPaused => _isPaused;
  bool get isRunning => _isRunning;
  int get restTimeRemaining => _restTimeRemaining;
  String get restMessage => _restMessage;
  bool get isCompleted => _isCompleted;

  // 총 훈련 진행률 (0.0 ~ 1.0)
  double get totalProgress {
    if (trainingList.isEmpty) return 0.0;
    if (_isCompleted) return 1.0; // 완료 시 항상 100%
    if (_isPaused) return _lastTotalProgress ?? 0.0; // 일시정지 상태면 마지막 진행도 반환

    // 완료된 훈련의 총 시간
    int completedTime = 0;
    for (int i = 0; i < _currentTrainingIndex; i++) {
      completedTime += trainingList[i].totalTime;
    }

    // 현재 훈련의 진행 시간
    int currentTrainingProgress = 0;
    if (_isResting) {
      // 현재 훈련의 사이클 시간은 모두 완료
      final current = trainingList[_currentTrainingIndex];
      currentTrainingProgress = current.cycle * current.count;
      // 휴식 진행도 추가 (남은 시간이 아닌 진행된 시간)
      currentTrainingProgress += (current.restTime - _restTimeRemaining);
    } else if (_startTime != null) {
      // 현재 훈련의 진행 시간 (최대 사이클 시간까지)
      final current = trainingList[_currentTrainingIndex];
      final elapsed = DateTime.now().difference(_startTime!) - _pausedDuration;
      final maxCycleTime = current.cycle * current.count;
      currentTrainingProgress = elapsed.inSeconds.clamp(0, maxCycleTime);
    }



    // 총 시간
    int totalTime = 0;
    for (var training in trainingList) {
      totalTime += training.totalTime;
    }

    if (totalTime == 0) return 1.0; // 예외 처리

    if (kDebugMode) {
      print("총 시간: $totalTime, 완료 시간: $completedTime, 현재 진행: $currentTrainingProgress");
      print("총 진행률: ${(completedTime + currentTrainingProgress) / totalTime}");
    }

    final progress = (completedTime + currentTrainingProgress) / totalTime;
    _lastTotalProgress = progress.clamp(0.0, 1.0); // 진행도가 100%를 넘지 않도록
    return _lastTotalProgress!;
  }

  // 현재 훈련의 진행률 (0.0 ~ 1.0) 수정
  double get currentProgress {
    if (_isCompleted) return 1.0;
    if (trainingList.isEmpty) return 0.0;
    if (_isPaused) return _lastCurrentProgress ?? 0.0; // 일시정지 상태면 마지막 진행도 반환

    final current = trainingList[_currentTrainingIndex];

    if (_isResting) {
      // 쉬는 시간 진행률 계산
      if (current.restTime <= 0) return 1.0;
      final progress = 1.0 - (_restTimeRemaining / current.restTime);
      _lastCurrentProgress = progress.clamp(0.0, 1.0); // 0~1 범위 보장
      return _lastCurrentProgress!;
    }

    if (_startTime == null) return 0.0;

    final totalCycleTime = current.cycle * current.count;
    if (totalCycleTime <= 0) return 0.0;

    final elapsed = DateTime.now().difference(_startTime!) - _pausedDuration;
    final progress = (elapsed.inMilliseconds / (totalCycleTime * 1000));
    _lastCurrentProgress = progress.clamp(0.0, 1.0); // 0~1 범위 보장
    return _lastCurrentProgress!;
  }

  String get formattedElapsedTime {
    if (_isResting) {
      return formatTime(_restTimeRemaining * 1000);
    }

    if (_startTime == null) return formatTime(0);

    // 완료 상태일 때는 stopTime 사용
    final now = _isCompleted ? _stopTime! :
    (_isPaused && _pauseStart != null ? _pauseStart! : DateTime.now());
    final elapsed = now.difference(_startTime!) - _pausedDuration;
    return formatTime(elapsed.inMilliseconds);
  }

  // 현재 훈련의 남은 시간
  String get formattedRemainingTime {
    if (_isCompleted) return "00:00:00.00"; // 완료 시 항상 0 표시
    if (_isResting) {
      return formatTime(_restTimeRemaining * 1000);
    }

    if (_startTime == null || _currentTrainingIndex >= trainingList.length) {
      return formatTime(0);
    }

    final current = trainingList[_currentTrainingIndex];
    final totalTime = current.cycle * current.count * 1000; // 총 시간 (밀리초)

    final now = _isPaused && _pauseStart != null ? _pauseStart! : DateTime.now();
    final elapsed = now.difference(_startTime!) - _pausedDuration;

    final remaining = totalTime - elapsed.inMilliseconds;
    return formatTime(remaining > 0 ? remaining : 0);
  }

  int calculateTotalTime() {
    int total = 0;
    for (var training in trainingList) {
      // cycle * count는 순수 훈련 시간
      total += training.cycle * training.count;
      // 쉬는 시간 포함 (마지막 훈련은 쉬는 시간 없음)
      if (trainingList.indexOf(training) < trainingList.length - 1) {
        total += training.restTime;
      }
    }
    return total;
  }

  String get timerButtonText => !_isRunning ? "시작" : (_isPaused ? "계속" : "정지");

  String get displayTitle {
    if (_isResting) {
      return "쉬는 시간";
    } else if (_currentTrainingIndex < trainingList.length) {
      return trainingList[_currentTrainingIndex].title;
    }
    return "";
  }

  void _playBeep() {
    _soundManager.playSound(beepSound);
    // 비프음 이벤트를 cycle_beep로 표시하여 다른 이벤트와 구분
    onEvent?.call("cycle_beep");
  }

  // 수정: 타이머 시작 메서드
  void startTraining() {
    // 이미 모든 훈련이 완료되었으면 시작하지 않음
    if (_isCompleted) {
      onUpdate();
      return;
    }

    _isRunning = true;
    _isPaused = false;
    _isFinalCycle = false;
    _currentCycleCount = 0;
    _pausedDuration = Duration.zero;
    _restMessage = "";

    // 첫 훈련인 경우 바로 시작
    if (_currentTrainingIndex == 0) {
      _isResting = false;
      _startActualTraining();
    } else {
      // 두 번째 훈련부터는 쉬는 시간부터 시작
      _startRestBeforeTraining();
    }
  }

  // 새로운 메서드: 실제 훈련 시작 (기존 startTraining 로직)
  void _startActualTraining() {
    if (_isCompleted) return;

    _isResting = false;
    _playBeep(); // 시작음

    // 시작 이벤트
    onEvent?.call("start");

    Future.delayed(const Duration(milliseconds: 2750), () {
      if (!_isRunning || _isPaused || _isCompleted) {
        return;
      }

      // 중요: 새로운 훈련마다 _startTime을 다시 설정
      _startTime = DateTime.now();
      _pausedDuration = Duration.zero; // 일시정지 시간도 초기화

      _cancelScheduledBeeps(); // 이전 비프음 취소
      _scheduleBeeps(); // 새로운 비프음 예약
      _startTimer(); // 타이머 시작
      onUpdate();
    });
  }


// 쉬는 시간 후 실제 훈련 시작
  void _startRestBeforeTraining() {
    _isResting = true;

    final current = trainingList[_currentTrainingIndex];
    _restTimeRemaining = current.restTime;

    onEvent?.call("rest_start");
    onUpdate();

    _restTimer?.cancel();
    _restTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isPaused || _isCompleted) return;

      if (_restTimeRemaining > 0) {
        _restTimeRemaining--;

        if (_restTimeRemaining == 10) {
          _restMessage = "10초 후 훈련이 시작됩니다";
          if (!_isCompleted) _playBeep();
        } else if (_restTimeRemaining < 10) {
          _restMessage = "$_restTimeRemaining초 후 훈련이 시작됩니다";
        }

        onUpdate();
      } else {
        _restTimer?.cancel();
        _isResting = false;
        _restMessage = "";

        // 쉬는 시간이 끝나면 실제 훈련 시작
        _startActualTraining();
      }
    });
  }

// 비프음 스케줄링 메서드 개선
  void _scheduleBeeps() {
    _cancelScheduledBeeps();

    if (_startTime == null) {
      if (kDebugMode) {
        print("경고: _startTime이 null입니다. 비프음을 예약할 수 없습니다.");
      }
      return;
    }

    final training = trainingList[_currentTrainingIndex];
    final intervalMs = training.interval * 1000;
    final cycleMs = training.cycle * 1000;
    final totalCycles = training.count;


    // 현재 시간과 시작 시간의 차이 계산
    final now = DateTime.now();
    final elapsedMs = now.difference(_startTime!).inMilliseconds - _pausedDuration.inMilliseconds;

    if (kDebugMode) {
      print("비프음 스케줄링 - 훈련 ${_currentTrainingIndex + 1}, 인원: $numPeople, 사이클: $totalCycles");
      print("경과 시간: ${elapsedMs}ms");
    }

    final Set<int> beepTimes = {};

    // 각 사람별로 비프음 예약
    for (int personIndex = 0; personIndex < numPeople; personIndex++) {
      int personStartTime = intervalMs * personIndex;

      for (int cycle = 0; cycle < totalCycles; cycle++) {
        // 마지막 훈련의 마지막 싸이클 처리


        int cycleStartTime = personStartTime + (cycleMs * cycle);
        int beepTime = cycleStartTime - 2750;
        int timeUntilBeep = beepTime - elapsedMs;

        if (timeUntilBeep > 0) {
          beepTimes.add(timeUntilBeep);

          if (kDebugMode) {
            print("비프음 예약 - 사람: ${personIndex + 1}/$numPeople, 싸이클: ${cycle + 1}/$totalCycles, ${timeUntilBeep}ms 후");
          }
        }
      }
    }

    final List<int> sortedBeepTimes = beepTimes.toList()..sort();

    if (kDebugMode) {
      print("훈련 ${_currentTrainingIndex + 1}: 총 ${sortedBeepTimes.length}개 비프음 예약됨");
    }

    for (final delay in sortedBeepTimes) {
      final t = Timer(Duration(milliseconds: delay), () {
        if (_isRunning && !_isPaused && !_isCompleted) {
          _playBeep();
          if (kDebugMode) {
            print("비프음 재생 - 훈련 ${_currentTrainingIndex + 1}");
          }
        }
      });
      _scheduledBeeps.add(t);
    }
  }

  void _cancelScheduledBeeps() {
    for (final t in _scheduledBeeps) {
      t.cancel();
    }
    _scheduledBeeps.clear();
  }

  void _startTimer() {
    if (_currentTrainingIndex >= trainingList.length) {
      _completeAllTraining();
      return;
    }

    final training = trainingList[_currentTrainingIndex];
    final cycleMs = training.cycle * 1000;
    final totalCycles = training.count;

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (_isPaused || _startTime == null) return;

      final now = DateTime.now();
      final elapsedMs = now.difference(_startTime!).inMilliseconds - _pausedDuration.inMilliseconds;

      // 현재 싸이클 계산
      int currentCycle = elapsedMs ~/ cycleMs;

      // 싸이클이 변경되었을 때만 업데이트
      if (currentCycle != _currentCycleCount && currentCycle < totalCycles) {
        _currentCycleCount = currentCycle;
        if (kDebugMode) {
          print("현재 싸이클: ${_currentCycleCount + 1}/$totalCycles");
        }
      }

      // 훈련 종료 조건
      if (elapsedMs >= cycleMs * totalCycles) {
        timer.cancel();
        _timer = null;
        _currentCycleCount = totalCycles - 1;
        _goToRestOrNextTraining();
        return;
      }

      onUpdate();
    });
  }
  void _completeAllTraining() {
    // 모든 타이머 중지
    _timer?.cancel();
    _timer = null;
    _restTimer?.cancel();
    _restTimer = null;
    _nextTrainingNotificationTimer?.cancel();
    _nextTrainingNotificationTimer = null;
    _cancelScheduledBeeps();

    // 상태 업데이트
    _isRunning = false;
    _isPaused = false;
    _isFinalCycle = true;
    _isResting = false;
    _isCompleted = true;

    // 완료 시 프로그레스바를 100%로 설정
    _lastTotalProgress = 1.0;
    _lastCurrentProgress = 1.0;

    // 시계 멈추기 위해 현재 시간 저장
    _stopTime = DateTime.now();

    // 완료 이벤트 발생
    onEvent?.call("complete");

    onUpdate();
  }

  // 훈련 이동 메서드 수정
  void _goToNextTraining() {
    _nextTrainingNotificationTimer?.cancel();

    if (_currentTrainingIndex < trainingList.length - 1) {
      _currentTrainingIndex++;
      _currentCycleCount = 0;

      // 다음 훈련을 위해 상태 초기화
      _startTime = null;
      _pausedDuration = Duration.zero;
      _isResting = false;
      _restMessage = "";

      if (kDebugMode) {
        print("다음 훈련으로 이동: ${_currentTrainingIndex + 1}/${trainingList.length}");
      }

      startTraining(); // 다시 시작
    } else {
      _completeAllTraining();
    }
  }

  void toggleTimer() {
    if (!_isRunning) {
      startTraining();
    } else if (_isPaused) {
      _resumeTimer();
    } else {
      _pauseTimer();
    }
  }

  void _pauseTimer() {
    _isPaused = true;
    _pauseStart = DateTime.now();

    // 현재 진행률 저장
    _lastTotalProgress = totalProgress;
    _lastCurrentProgress = currentProgress;

    _timer?.cancel();
    _restTimer?.cancel();
    _nextTrainingNotificationTimer?.cancel();
    _cancelScheduledBeeps();
    _soundManager.pauseSound();
    onUpdate();
    onEvent?.call("pause");
  }

  void _resumeTimer() {
    if (_pauseStart != null && _startTime != null) {
      final pauseDuration = DateTime.now().difference(_pauseStart!);
      _pausedDuration += pauseDuration;
    }

    _isPaused = false;
    _pauseStart = null;

    if (_isResting) {
      _restTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_isPaused) return;

        if (_restTimeRemaining > 0) {
          _restTimeRemaining--;

          if (_restTimeRemaining == 10) {
            _restMessage = "10초 후 훈련이 시작됩니다";
            _playBeep();
          } else if (_restTimeRemaining < 10) {
            _restMessage = "$_restTimeRemaining초 후 훈련이 시작됩니다";
          }

          onUpdate();
        } else {
          _restTimer?.cancel();
          _isResting = false;
          _restMessage = "";

          if (_currentTrainingIndex == 0) {
            _goToNextTraining();
          } else {
            _startActualTraining();
          }
        }
      });
    } else {
      _cancelScheduledBeeps();
      _scheduleBeeps();
      _startTimer();
    }

    _soundManager.resumeSound();
    onUpdate();
    onEvent?.call("resume");
  }

  void resetTimer() {
    _timer?.cancel();
    _timer = null;
    _restTimer?.cancel();
    _restTimer = null;
    _nextTrainingNotificationTimer?.cancel();
    _nextTrainingNotificationTimer = null;
    _lastTotalProgress = null;
    _lastCurrentProgress = null;
    _cancelScheduledBeeps();

    _isRunning = false;
    _isPaused = false;
    _isFinalCycle = false;
    _isResting = false;
    _isCompleted = false;
    _currentCycleCount = 0;
    _currentTrainingIndex = 0;
    _startTime = null;
    _pauseStart = null;
    _pausedDuration = Duration.zero;
    _restTimeRemaining = 0;
    _restMessage = "";

    onUpdate();
    onEvent?.call("reset");
  }

  void _goToRestOrNextTraining() {
    final current = trainingList[_currentTrainingIndex];

    if (current.restTime > 0 && _currentTrainingIndex < trainingList.length - 1) {
      _isResting = true;
      _restTimeRemaining = current.restTime;
      onEvent?.call("rest_start");

      _restTimer?.cancel();
      _restTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_isPaused) return;

        if (_restTimeRemaining > 0) {
          _restTimeRemaining--;

          if (_restTimeRemaining == 10) {
            _restMessage = "10초 후 다음 훈련이 시작됩니다";
            _playBeep();
          } else if (_restTimeRemaining < 10) {
            _restMessage = "$_restTimeRemaining초 후 다음 훈련이 시작됩니다";
          }

          onUpdate();
        } else {
          _restTimer?.cancel();
          _isResting = false;
          _restMessage = "";
          _goToNextTraining(); // 여기서 _goToNextTraining 호출
        }
      });
      onUpdate();
    } else {
      _goToNextTraining(); // 여기서도 _goToNextTraining 호출
    }
  }


  void dispose() {
    _timer?.cancel();
    _restTimer?.cancel();
    _nextTrainingNotificationTimer?.cancel();
    _cancelScheduledBeeps();
  }
}
