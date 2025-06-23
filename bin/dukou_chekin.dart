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

  // 打印调试信息
  print('=== 调试信息 ===');
  print('邮箱: ${email != null ? _maskEmail(email) : '未设置'}');
  print('密码: ${passwd != null ? _maskPassword(passwd) : '未设置'}');
  print('Server Key: ${serverKey != null ? '已设置' : '未设置'}');
  print('基础URL: $baseUrl');
  print('================');

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
      print('=== 错误详情 ===');
      print('程序执行出错: $e');
      print('使用的邮箱: ${_maskEmail(email)}');
      print('错误发生时间: ${DateTime.now()}');
      print('===============');
      exit(1);
    }
  } else {
    print('❌ 环境变量检查失败:');
    print('EMAIL_KEY: ${email != null ? '✅ 已设置' : '❌ 未设置'}');
    print('PASSWD_KEY: ${passwd != null ? '✅ 已设置' : '❌ 未设置'}');
    print('请设置EMAIL_KEY和PASSWD_KEY环境变量');
    exit(1);
  }
}

Future<String> login(String email, String passwd) async {
  print('🔐 尝试登录...');
  print('请求URL: $baseUrl/api/token');
  print('邮箱: ${_maskEmail(email)}');
  
  var response = await Dio().post(
    '$baseUrl/api/token',
    data: {
      'email': email,
      'passwd': passwd,
    },
  );
  
  print('登录响应状态码: ${response.statusCode}');
  print('登录响应数据: ${response.data}');
  
  // 处理响应数据
  dynamic responseData = response.data;
  Map<String, dynamic> map;
  
  if (responseData is String) {
    map = jsonDecode(responseData);
  } else if (responseData is Map<String, dynamic>) {
    map = responseData;
  } else {
    throw Exception('响应数据格式错误: ${responseData.runtimeType}');
  }
  
  // 检查token是否存在
  if (map['token'] == null) {
    print('❌ 登录失败详情:');
    print('邮箱: ${_maskEmail(email)}');
    print('返回码: ${map['ret']}');
    print('错误信息: ${map['msg']}');
    print('完整响应: $map');
    throw Exception('登录失败，未获取到token。响应: $map');
  }
  
  // 显示格式化的用户信息
  String username = map['username']?.toString() ?? '未知用户';
  print('✅ 登录成功，获取到token');
  print('👤 用户名: $username');
  print('🆔 用户ID: ${map['id']}');
  
  return map['token'].toString();
}

Future<String> checkin(String token) async {
  print('📝 开始签到...');
  print('请求URL: $baseUrl/api/user/checkin');
  print('Token: ${token.substring(0, 10)}...(已截取)');
  
  var response = await Dio(BaseOptions(
    headers: {
      'access-token': token,
    },
  )).get('$baseUrl/api/user/checkin');
  
  print('签到响应状态码: ${response.statusCode}');
  print('签到响应数据: ${response.data}');
  
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
        print('⚠️ $operationName 失败 (第 $attempt 次尝试): $e');
        print('等待 $retryDelaySeconds 秒后重试...');
        await Future.delayed(Duration(seconds: retryDelaySeconds));
        continue;
      } else {
        // 最后一次尝试失败或不可重试的错误
        print('❌ $operationName 最终失败 (第 $attempt 次尝试): $e');
        print('错误类型: ${e.runtimeType}');
        if (e is DioError) {
          print('DioError详情:');
          print('  类型: ${e.type}');
          print('  状态码: ${e.response?.statusCode}');
          print('  响应数据: ${e.response?.data}');
          print('  错误消息: ${e.message}');
        }
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
    
    // 格式化时间（北京时间）
    DateTime now = DateTime.now().toUtc().add(Duration(hours: 8));
    String timestamp = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    
    print('签到完成 [$timestamp]');
    print('┌─────────────────────────────');
    
    // 修正签到成功的判断逻辑：ret为1且包含流量信息表示成功
    bool isSuccess = ret == 1 && result.contains('获得');
    
    if (isSuccess) {
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
    
    // 格式化时间（北京时间）
    DateTime now = DateTime.now().toUtc().add(Duration(hours: 8));
    String timestamp = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    
    // 构建友好的消息格式
    StringBuffer message = StringBuffer();
    message.writeln('📅 签到时间: $timestamp (北京时间)');
    message.writeln('');
    
    // 修正签到成功的判断逻辑：ret为1且包含流量信息表示成功
    bool isSuccess = ret == 1 && result.contains('流量');
    
    if (isSuccess) {
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
    DateTime now = DateTime.now().toUtc().add(Duration(hours: 8));
    String timestamp = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    
    return '''📅 签到时间: $timestamp (北京时间)

⚠️ 签到结果解析失败
📝 原始响应: $rawMessage

🤖 Dukou自动签到程序''';
  }
}

// 掩码邮箱地址，保留前2位和@后的域名
String _maskEmail(String email) {
  if (email.isEmpty) return '***';
  
  int atIndex = email.indexOf('@');
  if (atIndex == -1) return '***';
  
  String localPart = email.substring(0, atIndex);
  String domain = email.substring(atIndex);
  
  if (localPart.length <= 2) {
    return '***$domain';
  } else {
    return '${localPart.substring(0, 2)}***$domain';
  }
}

// 掩码密码，只显示长度
String _maskPassword(String password) {
  if (password.isEmpty) return '未设置';
  return '****(长度: ${password.length})';
}
