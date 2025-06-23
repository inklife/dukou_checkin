import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

const String baseUrl = 'https://flzt.top';
const int maxRetries = 3; // 最大重试次数
const int retryDelaySeconds = 5; // 重试间隔秒数

void main(List<String> arguments) async {
  var email = Platform.environment['EMAIL_KEY'];
  var passwd = Platform.environment['PASSWD_KEY'];
  var serverKey = Platform.environment['SERVER_KEY'];

  if (email != null && passwd != null) {
    try {
      print('开始执行签到程序...');
      var token = await retryOnError(() => login(email, passwd), '登录');
      print('登录成功，开始签到...');
      var message = await retryOnError(() => checkin(token), '签到');
      _printFormattedCheckinResult(message);
      if (serverKey != null) {
        await sendCheckinMessage(serverKey, message);
      }
    } catch (e) {
      print('程序执行出错: $e');
      exit(1);
    }
  } else {
    print('请设置EMAIL_KEY和PASSWD_KEY环境变量');
    exit(1);
  }
}

Future<String> login(String email, String passwd) async {
  var response = await Dio().post(
    '$baseUrl/api/token',
    data: {
      'email': email,
      'passwd': passwd,
    },
  );
  
  // 处理响应数据
  dynamic responseData = response.data;
  Map<String, dynamic> map;
  
  if (responseData is String) {
    map = jsonDecode(responseData);
  } else if (responseData is Map<String, dynamic>) {
    map = responseData;
  } else {
    throw Exception('响应数据格式错误');
  }
  
  // 检查token是否存在
  if (map['token'] == null) {
    throw Exception('登录失败，未获取到token。响应: $map');
  }
  
  return map['token'].toString();
}

Future<String> checkin(String token) async {
  var response = await Dio(BaseOptions(
    headers: {
      'access-token': token,
    },
  )).get('$baseUrl/api/user/checkin');
  return response.data.toString();
}

Future<void> sendCheckinMessage(String serverKey, String msg) async {
  try {
    // 解析和格式化签到结果
    String formattedMessage = _formatCheckinMessage(msg);
    
    await retryOnError(() async {
      await Dio().post(
        'https://sctapi.ftqq.com/$serverKey.send',
        data: {
          'title': 'Dukou签到结果',
          'desp': formattedMessage,
        },
      );
    }, 'Server酱推送');
    print('Server酱推送成功');
  } catch (e) {
    print('Server酱推送失败: $e');
    // 推送失败不影响程序继续执行
  }
}

// 通用重试函数
Future<T> retryOnError<T>(Future<T> Function() operation, String operationName) async {
  for (int attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      return await operation();
    } catch (e) {
      if (attempt < maxRetries && _isRetryableError(e)) {
        print('$operationName 失败 (第 $attempt 次尝试): $e');
        print('等待 $retryDelaySeconds 秒后重试...');
        await Future.delayed(Duration(seconds: retryDelaySeconds));
        continue;
      } else {
        // 最后一次尝试失败或不可重试的错误
        rethrow;
      }
    }
  }
  throw Exception('不应该到达这里');
}

// 判断是否为可重试的错误
bool _isRetryableError(dynamic error) {
  if (error is DioError) {
    // 网络连接错误、超时错误等可以重试
    return error.type == DioErrorType.connectTimeout ||
           error.type == DioErrorType.receiveTimeout ||
           error.type == DioErrorType.sendTimeout ||
           error.type == DioErrorType.other;
  }
  return false;
}

// 格式化控制台输出的签到结果
void _printFormattedCheckinResult(String rawMessage) {
  try {
    // 解析JSON响应
    Map<String, dynamic> response = jsonDecode(rawMessage);
    
    String result = response['result'] ?? '未知结果';
    int ret = response['ret'] ?? -1;
    
    // 格式化时间
    DateTime now = DateTime.now();
    String timestamp = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    
    print('签到完成 [$timestamp]');
    print('┌─────────────────────────────');
    if (ret == 0) {
      print('│ ✅ 签到状态: 成功');
      print('│ 📝 签到结果: $result');
    } else {
      print('│ ❌ 签到状态: 失败');
      print('│ 📝 错误信息: $result');
      print('│ 🔢 错误代码: $ret');
    }
    print('└─────────────────────────────');
  } catch (e) {
    // 如果解析失败，显示原始消息
    print('签到完成: $rawMessage');
  }
}

// 格式化签到消息
String _formatCheckinMessage(String rawMessage) {
  try {
    // 解析JSON响应
    Map<String, dynamic> response = jsonDecode(rawMessage);
    
    String result = response['result'] ?? '未知结果';
    int ret = response['ret'] ?? -1;
    
    // 格式化时间
    DateTime now = DateTime.now();
    String timestamp = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    
    // 构建友好的消息格式
    StringBuffer message = StringBuffer();
    message.writeln('📅 签到时间: $timestamp');
    message.writeln('');
    
    if (ret == 0) {
      message.writeln('✅ 签到状态: 成功');
      message.writeln('');
      message.writeln('📝 签到结果: $result');
    } else {
      message.writeln('❌ 签到状态: 失败');
      message.writeln('');
      message.writeln('📝 错误信息: $result');
      message.writeln('');
      message.writeln('🔢 错误代码: $ret');
    }
    
    message.writeln('');
    message.writeln('🤖 Dukou自动签到程序');
    
    return message.toString();
  } catch (e) {
    // 如果解析失败，返回原始消息
    DateTime now = DateTime.now();
    String timestamp = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    
    return '''📅 签到时间: $timestamp

⚠️ 签到结果解析失败
📝 原始响应: $rawMessage

🤖 Dukou自动签到程序''';
  }
}
