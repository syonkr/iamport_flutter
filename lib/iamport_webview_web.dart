import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Flutter Web 전용 IamportWebView
///
/// [userCode]와 [paymentData]를 이용해 결제 요청을 실행하며, 결제 결과는
/// IFrame 내부의 JavaScript에서 postMessage를 통해 부모(Flutter)로 전달됩니다.
/// 전달받은 결과는 [useQueryData] 콜백을 통해 외부로 전달됩니다.
class IamportWebViewWeb extends StatefulWidget {
  /// 상단 AppBar (옵션)
  final PreferredSizeWidget? appBar;

  /// 결제 진행 전 표시할 로딩 위젯 등 (옵션)
  final Widget? initialChild;

  /// iamport에 등록된 사용자 코드
  final String userCode;

  /// 결제 요청 시 필요한 파라미터를 담은 Map
  final Map<String, dynamic> paymentData;

  /// 결제 완료 후 전달된 결과 데이터를 받기 위한 콜백
  final ValueSetter<Map<String, String>> useQueryData;

  /// PG 별 추가 동작을 위한 콜백 (옵션)
  final Function? customPGAction;
  final Function isPaymentOver;

  final String? redirectUrl;

  IamportWebViewWeb({
    Key? key,
    this.appBar,
    this.initialChild,
    required this.userCode,
    required this.paymentData,
    required this.useQueryData,
    required this.isPaymentOver,
    this.redirectUrl,
    this.customPGAction,
  }) : super(key: key);

  @override
  _IamportWebViewWebState createState() => _IamportWebViewWebState();
}

class _IamportWebViewWebState extends State<IamportWebViewWeb> {
  late final String _iframeElementId;
  StreamSubscription<html.MessageEvent>? _messageSub;

  @override
  void initState() {
    super.initState();
    _iframeElementId =
        'iamport_iframe_${DateTime.now().millisecondsSinceEpoch}';

    // IFrame에 표시할 HTML 콘텐츠 생성 후, platform view로 등록
    ui.platformViewRegistry.registerViewFactory(_iframeElementId, (int viewId) {
      final String content = _buildHtmlContent();
      final String dataUri =
          'data:text/html;charset=utf-8,' + Uri.encodeComponent(content);
      final html.IFrameElement element = html.IFrameElement()
        ..src = dataUri
        ..style.border = 'none'
        ..width = '100%'
        ..height = '100%';
      return element;
    });

    // IFrame 내부에서 postMessage로 전달하는 이벤트 수신 (예: 결제 완료, custom PG 액션)
    _messageSub = html.window.onMessage.listen((html.MessageEvent event) {
      if (event.data != null && event.data is Map) {
        final Map data = event.data;
        if (data['type'] == 'customPGAction') {
          // customPGAction 이벤트 수신 (예: 특수 PG 처리)
          if (widget.customPGAction != null) {
            widget.customPGAction!(data['data']);
          }
        } else if (data['type'] == 'urlChange') {
          if (widget.isPaymentOver(data['url'])) {
            String decodedUrl = Uri.decodeComponent(data['url']);
            widget.useQueryData(Uri.parse(decodedUrl).queryParameters);
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    super.dispose();
  }

  /// IFrame에 로드할 HTML 콘텐츠를 동적으로 생성합니다.
  ///
  /// 여기에서는 iamport.js를 로드하고, 페이지 로드시 결제 요청을 실행하는
  /// initiatePayment() 함수를 포함합니다.
  String _buildHtmlContent() {
    final String paymentDataJson = jsonEncode(widget.paymentData);
    return '''
    <!DOCTYPE html>
    <html>
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
        <script type="text/javascript" src="https://cdn.iamport.kr/v1/iamport.js"></script>
        <script type="text/javascript">
          function initiatePayment() {
            IMP.init("${widget.userCode}");
            IMP.request_pay($paymentDataJson, function(response) {
              const query = [];
              Object.keys(response).forEach(function(key) {
                query.push(key + "=" + response[key]);
              });
              window.parent.postMessage({type: 'urlChange', url: "${widget.redirectUrl}" + "?" + query.join("&")}, "*");
            });
          }

          // URL 변경(리다이렉트) 감지를 위한 예시: hashchange 이벤트 또는 setInterval 방식
          function checkUrlChange() {
            var currentUrl = window.location.href;
            window.parent.postMessage({type: 'urlChange', url: currentUrl}, "*");
          }

          window.onload = initiatePayment;
        </script>
      </head>
      <body></body>
    </html>
    ''';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.appBar,
      body: HtmlElementView(viewType: _iframeElementId),
    );
  }
}
