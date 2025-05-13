import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:swim/features/training/models/training_session.dart';

class TrainingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // 훈련 세션 저장
  Future<String> saveTrainingSession(TrainingSession session) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception('사용자가 로그인되지 않았습니다');

      final docRef = await _firestore
          .collection('training_sessions')
          .add(session.toFirestore());

      return docRef.id;
    } catch (e) {
      throw Exception('훈련 저장 실패: $e');
    }
  }

  // 훈련 세션 가져오기
  Future<TrainingSession?> getTrainingSession(String sessionId) async {
    try {
      final doc = await _firestore
          .collection('training_sessions')
          .doc(sessionId)
          .get();

      if (!doc.exists) return null;

      return TrainingSession.fromFirestore(doc, null);
    } catch (e) {
      throw Exception('훈련 불러오기 실패: $e');
    }
  }

  // 사용자의 모든 훈련 세션 가져오기
  Stream<List<TrainingSession>> getUserTrainingSessions() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);

    return _firestore
        .collection('training_sessions')
        .where('userId', isEqualTo: user.uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
        .map((doc) => TrainingSession.fromFirestore(doc, null))
        .toList());
  }

  // 훈련 완료 상태 업데이트
  Future<void> updateTrainingComplete(String sessionId) async {
    try {
      await _firestore
          .collection('training_sessions')
          .doc(sessionId)
          .update({
        'isCompleted': true,
        'completedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('훈련 완료 업데이트 실패: $e');
    }
  }

  // 실시간 훈련 진행 상태 업데이트
  Future<void> updateTrainingProgress(
      String sessionId,
      int currentIndex,
      int currentCycle,
      double progress,
      ) async {
    try {
      await _firestore
          .collection('training_sessions')
          .doc(sessionId)
          .update({
        'currentProgress': {
          'trainingIndex': currentIndex,
          'cycleIndex': currentCycle,
          'progressPercent': progress,
          'updatedAt': FieldValue.serverTimestamp(),
        }
      });
    } catch (e) {
      // 실시간 업데이트는 실패해도 계속 진행
      print('진행 상태 업데이트 실패: $e');
    }
  }
}