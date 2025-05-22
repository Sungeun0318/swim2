// lib/features/training_generation/tg_timer_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';
import 'package:swim/features/swimming/models/training_detail_data.dart';
import 'package:swim/features/training_generation/models/training_session.dart';
import 'package:swim/repositories/training_repository.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:swim/features/training_generation/controllers/tg_timer_controller.dart';
import 'tg_result_screen.dart';

class TGTimerScreen extends StatefulWidget {
  final String sessionId;
  final TrainingSession? fallbackData;

  const TGTimerScreen({
    Key? key,
    required this.sessionId,
    this.fallbackData,
  }) : super(key: key);

  @override
  State<TGTimerScreen> createState() => _TGTimerScreenState();
}

class _TGTimerScreenState extends State<TGTimerScreen> with SingleTickerProviderStateMixin {
  late TGTimerController _timerController;
  late VideoPlayerController _videoController;
  Timer? _uiUpdateTimer;
  Timer? _progressUpdateTimer;
  bool _videoInitialized = false;
  bool _isVideoError = false;

  final TrainingRepository _trainingRepository = TrainingRepository();
  TrainingSession? _trainingSession;
  bool _isLoading = true;
  bool _isOfflineMode = false;

  // 추가: 카운트다운 관련 변수
  bool _isCountingDown = false;
  int _countdownValue = 5;
  late AnimationController _flashAnimationController;
  late Animation<Color?> _flashAnimation;

  @override
  void initState() {
    super.initState();
    _loadTrainingSession();

    // 깜빡임 애니메이션 컨트롤러 초기화
    _flashAnimationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    // 빨간색 <-> 원래 배경색 애니메이션
    _flashAnimation = ColorTween(
      begin: Colors.white,
      end: Colors.red.withOpacity(0.3),
    ).animate(_flashAnimationController)
      ..addListener(() {
        setState(() {});
      })
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _flashAnimationController.reverse();
        } else if (status == AnimationStatus.dismissed && _isCountingDown) {
          _flashAnimationController.forward();
        }
      });
  }

  Future<void> _loadTrainingSession() async {
    try {
      // Firebase에서 데이터 로드 시도
      final session = await _trainingRepository.getTrainingSession(widget.sessionId);

      if (session == null && widget.fallbackData != null) {
        // 오프라인 모드 (fallback 데이터 사용)
        setState(() {
          _trainingSession = widget.fallbackData;
          _isOfflineMode = true;
          _isLoading = false;
        });
        if (kDebugMode) {
          print("오프라인 모드: Fallback 데이터 사용");
        }
      } else if (session != null) {
        setState(() {
          _trainingSession = session;
          _isLoading = false;
        });
        if (kDebugMode) {
          print("Firebase에서 훈련 데이터 로드 성공");
        }
      } else {
        throw Exception('훈련 데이터를 찾을 수 없습니다');
      }

      // 컴포넌트 초기화
      _initializeComponents();

    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('데이터 로드 실패: $e')),
        );
      }
      Navigator.pop(context);
    }
  }

  void _initializeComponents() {
    if (_trainingSession == null) return;

    // 타이머 컨트롤러 초기화
    _timerController = TGTimerController(
      trainingList: _trainingSession!.trainings,
      beepSound: _trainingSession!.beepSound,
      numPeople: _trainingSession!.numPeople,
      onUpdate: () {
        if (mounted) setState(() {});
      },
      onEvent: _handleTimerEvent,
    );

    // 비디오 컨트롤러 초기화
    _initVideoPlayer();

    // UI 업데이트 타이머
    _uiUpdateTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (mounted) setState(() {});
    });

    // 진행 상태 업데이트 타이머 (10초마다 Firebase 업데이트)
    _progressUpdateTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _updateProgressToFirebase();
    });
  }

  Future<void> _initVideoPlayer() async {
    try {
      if (kDebugMode) {
        print("비디오 초기화 시작");
      }

      const videoPath = 'assets/videos/swim.mp4';
      _videoController = VideoPlayerController.asset(videoPath);

      await _videoController.initialize().then((_) {
        if (kDebugMode) {
          print("비디오 초기화 성공");
        }

        _videoController.setLooping(true);
        _videoController.setVolume(1.0);

        if (mounted) {
          setState(() {
            _videoInitialized = true;
          });
        }
      }).catchError((error) {
        if (kDebugMode) {
          print("비디오 초기화 실패: $error");
        }

        _isVideoError = true;
        if (mounted) setState(() {});
      });
    } catch (e) {
      _isVideoError = true;
      if (kDebugMode) {
        print("비디오 초기화 에러: $e");
      }
      if (mounted) setState(() {});
    }
  }

  // 타이머 이벤트 처리
  Future<void> _handleTimerEvent(String action) async {
    if (!mounted || _trainingSession == null) return;

    try {
      switch (action) {
        case "start":
        // 훈련 시작 시 2.75초 후 비디오 재생
          Future.delayed(const Duration(milliseconds: 2750), () {
            if (mounted && !_timerController.isResting && _videoInitialized && _videoController.value.isInitialized) {
              _videoController.play();
            }
          });
          break;

        case "rest_start":
        // 쉬는 시간 시작 시 비디오 일시정지
          if (_videoInitialized && _videoController.value.isInitialized) {
            _videoController.pause();
          }
          break;

        case "complete":
        // 훈련 완료 시 처리
          await _completeTraining();
          break;

        case "pause":
        // 일시정지 시 비디오도 정지
          if (_videoInitialized && _videoController.value.isInitialized) {
            _videoController.pause();
          }
          break;

        case "resume":
        // 재개 시 비디오도 재생 (쉬는 시간이 아닌 경우)
          if (!_timerController.isResting && _videoInitialized && _videoController.value.isInitialized) {
            _videoController.play();
          }
          break;

        case "reset":
        // 초기화
          if (_videoInitialized && _videoController.value.isInitialized) {
            _videoController.pause();
            _videoController.seekTo(Duration.zero);
          }
          break;

        default:
          break;
      }
    } catch (e) {
      if (kDebugMode) {
        print("이벤트 처리 에러: $e");
      }
    }
  }

  // 훈련 완료 시 결과 화면으로 이동
  Future<void> _completeTraining() async {
    // Firebase에 완료 상태 업데이트
    if (!_isOfflineMode) {
      try {
        await _trainingRepository.updateTrainingComplete(widget.sessionId);
        if (kDebugMode) {
          print("Firebase에 훈련 완료 상태 업데이트 성공");
        }
      } catch (e) {
        if (kDebugMode) {
          print("Firebase 업데이트 실패: $e");
        }
      }
    }

    // 비디오 정지
    if (_videoInitialized && _videoController.value.isInitialized) {
      _videoController.pause();
      _videoController.seekTo(Duration.zero);
    }

    // 결과 화면으로 이동
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => TGResultScreen(
            sessionId: widget.sessionId,
            session: _trainingSession!,
            totalElapsedTime: _timerController.formattedElapsedTime,
          ),
        ),
      );
    }
  }

  // 진행 상태를 Firebase에 업데이트
  Future<void> _updateProgressToFirebase() async {
    if (_isOfflineMode || !_timerController.isRunning) return;

    try {
      await _trainingRepository.updateTrainingProgress(
        widget.sessionId,
        _timerController.currentTrainingIndex,
        _timerController.currentCycleIndex,
        _timerController.totalProgress,
      );
      if (kDebugMode) {
        print("진행 상태 업데이트: ${(_timerController.totalProgress * 100).toInt()}%");
      }
    } catch (e) {
      if (kDebugMode) {
        print("진행 상태 업데이트 실패: $e");
      }
    }
  }

  @override
  void dispose() {
    _flashAnimationController.dispose();
    _timerController.dispose();
    if (_videoInitialized) {
      _videoController.dispose();
    }
    _uiUpdateTimer?.cancel();
    _progressUpdateTimer?.cancel();
    super.dispose();
  }

  // 타이머 토글 (시작/일시정지/재개)
  Future<void> _handleToggle() async {
    if (!mounted) return;

    try {
      if (_timerController.isCompleted) {
        _handleReset();
        return;
      }

      // 타이머가 시작되지 않은 상태에서 시작 버튼을 누른 경우
      if (!_timerController.isRunning) {
        // 5초 카운트다운 시작
        _startCountdown();
      }
      // 타이머가 일시정지된 상태에서 계속 버튼을 누른 경우
      else if (_timerController.isPaused) {
        _timerController.toggleTimer(); // 타이머 재개
        if (!_timerController.isResting && _videoInitialized && _videoController.value.isInitialized) {
          _videoController.play();
        }
      }
      // 타이머가 실행 중인 상태에서 정지 버튼을 누른 경우
      else {
        _timerController.toggleTimer(); // 타이머 일시정지
        if (_videoInitialized && _videoController.value.isInitialized) {
          _videoController.pause();
        }
      }

      if (mounted) setState(() {});
    } catch (e) {
      if (kDebugMode) {
        print("토글 에러: $e");
      }
    }
  }

  // 5초 카운트다운 메서드 (새로 추가, 소리 없음)
  void _startCountdown() {
    setState(() {
      _isCountingDown = true;
      _countdownValue = 5;
    });

    // 깜빡임 애니메이션 시작
    _flashAnimationController.forward();

    // 카운트다운 타이머
    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        _countdownValue--;
      });

      // 카운트다운 종료
      if (_countdownValue <= 0) {
        timer.cancel();
        setState(() {
          _isCountingDown = false;
        });

        // 깜빡임 중지
        _flashAnimationController.stop();
        _flashAnimationController.reset();

        // 실제 타이머 시작
        _timerController.startTraining();
      }
    });
  }

  // 타이머 리셋
  Future<void> _handleReset() async {
    if (!mounted) return;

    try {
      _timerController.resetTimer();
      if (_videoInitialized && _videoController.value.isInitialized) {
        _videoController.pause();
        _videoController.seekTo(Duration.zero);
      }

      if (mounted) setState(() {});
    } catch (e) {
      if (kDebugMode) {
        print("초기화 에러: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: const Center(
          child: CircularProgressIndicator(color: Colors.pink),
        ),
      );
    }

    if (_trainingSession == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              const Text('훈련 데이터를 불러올 수 없습니다'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('돌아가기'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      // 카운트다운 중일 때 배경색 애니메이션 적용
      backgroundColor: _isCountingDown
          ? _flashAnimation.value
          : Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          "Training Generation",
          style: TextStyle(
            color: Colors.pink,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_isOfflineMode)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Icon(Icons.cloud_off, color: Colors.yellow),
            ),
        ],
      ),
      // 카운트다운 중이면 카운트다운 UI 표시, 아니면 기존 UI
      body: _isCountingDown
          ? _buildCountdownUI()
          : _buildTimerUI(),
    );
  }

  // 카운트다운 UI 위젯
  Widget _buildCountdownUI() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            '훈련 시작',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              color: Colors.black,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$_countdownValue',
                style: const TextStyle(
                  fontSize: 80,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 40),
          const Text(
            '준비하세요!',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  // 기존 타이머 UI 위젯
  Widget _buildTimerUI() {
    return SingleChildScrollView(
      child: Column(
        children: [
          // 쉬는 시간일 때는 비디오 대신 휴식 표시
          if (_timerController.isResting)
            Container(
              width: double.infinity,
              height: 220,
              color: Colors.cyan.shade100,
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.timer_outlined,
                    size: 80,
                    color: Colors.blue,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "쉬는 시간",
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "남은 시간: ${_timerController.restTimeRemaining}초",
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                  if (_timerController.restMessage.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _timerController.restMessage,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.deepOrange,
                        ),
                      ),
                    ),
                ],
              ),
            )
          else if (_videoInitialized && _videoController.value.isInitialized)
          // 비디오가 초기화되었고 준비된 경우
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: AspectRatio(
                aspectRatio: _videoController.value.aspectRatio,
                child: VideoPlayer(_videoController),
              ),
            )
          else if (_isVideoError)
            // 비디오 오류 발생 시 대체 UI
              Container(
                width: double.infinity,
                height: 220,
                color: Colors.black,
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, color: Colors.red, size: 40),
                      SizedBox(height: 8),
                      Text(
                        "비디오를 로드할 수 없습니다",
                        style: TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              )
            else
            // 비디오 로딩 중 표시
              Container(
                width: double.infinity,
                height: 220,
                color: Colors.black,
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),

          const SizedBox(height: 20),

          // 타이틀 및 상태 표시
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.black, width: 2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _timerController.displayTitle,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
          ),

          const SizedBox(height: 10),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _timerController.isResting ? Colors.cyan : Colors.black,
              borderRadius: BorderRadius.circular(8),
            ),
            child: _timerController.isResting
                ? Text(
              "휴식",
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            )
                : Text(
              "${_timerController.currentCycleIndex + 1}/${_timerController.currentTrainingIndex < _trainingSession!.trainings.length ? _trainingSession!.trainings[_timerController.currentTrainingIndex].count : 0} ${_timerController.currentTrainingIndex < _trainingSession!.trainings.length ? _trainingSession!.trainings[_timerController.currentTrainingIndex].distance : 0}M",
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.cyan),
            ),
          ),

          const SizedBox(height: 10),

          // 타이머 및 남은 시간 표시
          Text(
            _timerController.formattedElapsedTime,
            style: const TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.bold,
              color: Colors.red,
            ),
          ),

          // 남은 시간 표시
          Text(
            "남은 시간: ${_timerController.formattedRemainingTime}",
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.orange,
            ),
          ),

          const SizedBox(height: 10),

          Text(
            _timerController.isResting
                ? "휴식 시간"
                : "싸이클: ${_timerController.currentCycleTime}초",
            style: TextStyle(
              fontSize: 20,
              color: _timerController.isResting ? Colors.blue : Colors.cyan,
            ),
          ),

          const SizedBox(height: 20),

          // 전체 진행 상황 프로그레스 바
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "전체 진행 상황",
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      _timerController.isCompleted
                          ? "100%"
                          : "${(_timerController.totalProgress * 100).toInt()}%",
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: _timerController.isCompleted
                        ? 1.0
                        : _timerController.totalProgress,
                    backgroundColor: Colors.grey[300],
                    color: Colors.pink,
                    minHeight: 10,
                  ),
                ),
              ],
            ),
          ),

          // 현재 훈련 진행 상황 프로그레스 바
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "현재 진행",
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      "${(_timerController.currentProgress * 100).toInt()}%",
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: _timerController.currentProgress,
                    backgroundColor: Colors.grey[300],
                    color: _timerController.isResting ? Colors.blue : Colors.cyan,
                    minHeight: 10,
                  ),
                ),
              ],
            ),
          ),

          // 완료 메시지 (훈련 완료시)
          if (_timerController.isCompleted)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                "모든 훈련을 완료했습니다! 수고하셨습니다.",
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold
                ),
              ),
            ),

          const SizedBox(height: 20),

          // 버튼들
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: _handleToggle,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 14),
                ),
                child: Text(
                  _timerController.timerButtonText,
                  style: const TextStyle(color: Colors.pink, fontSize: 20),
                ),
              ),
              const SizedBox(width: 20),
              ElevatedButton(
                onPressed: _handleReset,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 14),
                ),
                child: const Text(
                  "초기화",
                  style: TextStyle(color: Colors.pink, fontSize: 20),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          ElevatedButton(
            onPressed: () {
              // 훈련이 완료된 경우 결과 화면으로, 아닌 경우 뒤로가기
              if (_timerController.isCompleted) {
                _completeTraining();
              } else {
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
              shape: RoundedRectangleBorder(
                side: const BorderSide(color: Colors.black, width: 2),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              _timerController.isCompleted ? '결과 보기' : '훈련 종료',
              style: const TextStyle(color: Colors.black, fontSize: 20),
            ),
          ),

          const SizedBox(height: 30),
        ],
      ),
    );
  }
}