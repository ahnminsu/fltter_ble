import 'package:get/get.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class BehaviorPrediction {
  OrtSession? session;
  List<int> predictionBuffer = [];
  final RxString predictedBehavior = '정지'.obs; // 예측된 행동 상태

  // 행동 클래스 레이블
  final Map<int, String> classLabels = {
    0: "뛰기",
    1: "정지",
    2: "걷기"
  };

  // 생성자: ONNX 모델을 로드하고 세션을 초기화
  BehaviorPrediction() {
    _loadModel();
  }

  // ONNX 모델을 로드하는 메서드
  Future<void> _loadModel() async {
    try {
      OrtEnv env = OrtEnv.instance;

      // 'assets/wandb_model.onnx' 파일을 로드
      final ByteData data = await rootBundle.load('assets/model/wandb_model.onnx');
      final buffer = data.buffer;

      // 임시 디렉토리에 ONNX 파일 저장
      Directory tempDir = await getTemporaryDirectory();
      String tempPath = '${tempDir.path}/wandb_model.onnx';

      File modelFile = await File(tempPath).writeAsBytes(
        buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );

      // ONNX 세션 초기화
      OrtSessionOptions options = OrtSessionOptions();
      session = OrtSession.fromFile(modelFile, options);

      print("ONNX 모델 로드 성공!");
    } catch (e) {
      print("ONNX 모델 로드 실패: $e");
    }
  }

  // 버퍼에 데이터를 수집하고 예측 실행
  void processCompleteData(List<double> sensorData) {
    if (session == null) {
      print("세션이 초기화되지 않았습니다.");
      return;
    }

    try {
      // 입력 데이터를 3차원으로 변환
      Float32List inputTensorData = Float32List.fromList(sensorData);
      OrtValueTensor inputTensor = OrtValueTensor.createTensorWithDataList(
          [inputTensorData],
          [1, sensorData.length, 1] // [batch_size, sequence_length, feature_dimension]
      );

      // ONNX 모델 실행
      final Map<String, OrtValue> input = {'conv1d_input': inputTensor};
      List<OrtValue?> outputs = session!.run(OrtRunOptions(), input, ['dense_1']);
      OrtValueTensor outputTensor = outputs.first as OrtValueTensor;
      List<double> output = (outputTensor.value as List<List<double>>).first;

      int predictedIndex = output.indexOf(output.reduce((a, b) => a > b ? a : b));
      predictionBuffer.add(predictedIndex);

      if (predictionBuffer.length >= 10) {
        _predictBehavior();
        predictionBuffer.clear(); // 예측 후 버퍼 초기화
      }
    } catch (e) {
      print("예측 오류: $e");
    }
  }

  // 예측을 기반으로 행동 상태 업데이트
  void _predictBehavior() {
    try {
      // 버퍼에 있는 데이터를 기반으로 예측 실행
      Map<int, int> frequencyMap = {};
      for (var index in predictionBuffer) {
        frequencyMap[index] = (frequencyMap[index] ?? 0) + 1;
      }

      // 가장 빈도가 높은 인덱스를 선택
      int mostFrequentIndex = frequencyMap.entries
          .reduce((a, b) => a.value > b.value ? a : b)
          .key;

      // 정지, 걷기, 뛰기로 분류
      if (mostFrequentIndex == 0 ) { // 뛰기
        predictedBehavior.value = '뛰기';
      } else if (mostFrequentIndex == 2) { // 걷기
        predictedBehavior.value = '걷기';
      } else { // 나머지 행동 (정지)
        predictedBehavior.value = '정지';
      }

      // 예측된 행동 상태 출력
      print("예측된 행동: ${predictedBehavior.value}");
    } catch (e) {
      print("예측 수행 중 오류: $e");
    }
  }
}
