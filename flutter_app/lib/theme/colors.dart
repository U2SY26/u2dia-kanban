import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// U2DIA AI 칸반보드 색상 시스템
/// Salesforce Lightning Dark Mode 기반 색상 토큰
class AppColors {
  // 브랜드 색상
  static const Color brand = Color(0xFF0176D3);
  static const Color brandLight = Color(0xFF1B96FF);
  static const Color brandDark = Color(0xFF014486);
  static const Color brandBg = Color(0x141B96FF); // brandLight with 8% opacity

  // 배경 계층 시스템
  static const Color background = Color(0xFF0d1117);
  static const Color backgroundElevated = Color(0xFF161b22);
  static const Color panel = Color(0xFF21262d);
  static const Color card = Color(0xFF30363d);
  static const Color cardHover = Color(0xFF484f58);

  // 텍스트 색상
  static const Color textPrimary = Color(0xFFe6edf3);
  static const Color textSecondary = Color(0xFF8b949e);
  static const Color textMuted = Color(0xFF5e6c84);
  static const Color textInverse = Color(0xFF16181d);

  // 테두리 & 구분선
  static const Color border = Color(0xFF30363d);
  static const Color borderLight = Color(0x14FFFFFF); // white with 8% opacity
  static const Color borderFocus = Color(0xFF1B96FF);
  static const Color divider = Color(0x08FFFFFF); // white with 3% opacity

  // 시맨틱 색상
  static const Color success = Color(0xFF4BCA81);
  static const Color successBg = Color(0x1A4BCA81); // success with 10% opacity
  static const Color error = Color(0xFFEA001E);
  static const Color errorBg = Color(0x14EA001E); // error with 8% opacity
  static const Color warning = Color(0xFFFE9339);
  static const Color warningBg = Color(0x14FE9339); // warning with 8% opacity
  static const Color info = Color(0xFF1FC9E8);
  static const Color infoBg = Color(0x141FC9E8); // info with 8% opacity

  // 칸반 컬럼 상태 색상
  static const Color statusBacklog = Color(0xFF5e6c84);
  static const Color statusTodo = Color(0xFF8B5CF6);
  static const Color statusInProgress = Color(0xFF1B96FF);
  static const Color statusReview = Color(0xFFFE9339);
  static const Color statusDone = Color(0xFF4BCA81);
  static const Color statusBlocked = Color(0xFFEA001E);

  // 우선순위 색상
  static const Color priorityCritical = Color(0xFFEA001E);
  static const Color priorityHigh = Color(0xFFFE9339);
  static const Color priorityMedium = Color(0xFFE4A201);
  static const Color priorityLow = Color(0xFF4BCA81);

  // 차트 색상 팔레트
  static const Color chartBlue = Color(0xFF1B96FF);
  static const Color chartGreen = Color(0xFF4BCA81);
  static const Color chartRed = Color(0xFFFF5D2D);
  static const Color chartOrange = Color(0xFFFE9339);
  static const Color chartPurple = Color(0xFF8B5CF6);
  static const Color chartCyan = Color(0xFF1FC9E8);
  static const Color chartYellow = Color(0xFFE4A201);
  static const Color chartGray = Color(0xFF5e6c84);

  // 상태별 배경색 (투명도 적용)
  static Color get statusBacklogBg => statusBacklog.withOpacity(0.08);
  static Color get statusTodoBg => statusTodo.withOpacity(0.08);
  static Color get statusInProgressBg => statusInProgress.withOpacity(0.08);
  static Color get statusReviewBg => statusReview.withOpacity(0.08);
  static Color get statusDoneBg => statusDone.withOpacity(0.08);
  static Color get statusBlockedBg => statusBlocked.withOpacity(0.08);

  // 투명도 헬퍼
  static Color withAlpha(Color color, double opacity) {
    return color.withOpacity(opacity);
  }

  // 시스템 UI 오버레이 색상
  static const SystemUiOverlayStyle systemUiOverlayStyle = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF0d1117),
  );
}