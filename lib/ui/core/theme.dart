import 'package:flutter/material.dart';

/// 一套配色。数值照搬 Penna `lib/ui/core/theme.dart`(浅色 / 深色),另加预览底色。
class _Palette {
  const _Palette({
    required this.page,
    required this.bg,
    required this.sidebar,
    required this.card,
    required this.editorBg,
    required this.stage,
    required this.border,
    required this.slate50,
    required this.slate100,
    required this.slate400,
    required this.slate500,
    required this.slate700,
    required this.text,
    required this.primary,
    required this.primaryBg,
    required this.primaryBorder,
    required this.accent,
    required this.amber,
    required this.lock,
    required this.lockBorder,
    required this.lockText,
    required this.diffAdd,
    required this.diffAddText,
    required this.diffDel,
    required this.diffDelText,
    required this.toast,
    required this.shadow,
  });

  final Color page, bg, sidebar, card, editorBg, stage, border;
  final Color slate50, slate100, slate400, slate500, slate700, text;
  final Color primary, primaryBg, primaryBorder, accent, amber;
  final Color lock, lockBorder, lockText;
  final Color diffAdd, diffAddText, diffDel, diffDelText;
  final Color toast, shadow;
}

const _light = _Palette(
  page: Color(0xFFE9ECF0),
  bg: Color(0xFFF8F9FA),
  sidebar: Color(0xFFF1F3F5),
  card: Color(0xFFFFFFFF),
  editorBg: Color(0xFFFCFDFD),
  stage: Color(0xFFEEF1F4),
  border: Color(0xFFE2E8F0),
  slate50: Color(0xFFF8FAFC),
  slate100: Color(0xFFF1F5F9),
  slate400: Color(0xFF94A3B8),
  slate500: Color(0xFF64748B),
  slate700: Color(0xFF334155),
  text: Color(0xFF0F172A),
  primary: Color(0xFF2563EB),
  primaryBg: Color(0xFFEFF6FF),
  primaryBorder: Color(0xFFBFDBFE),
  accent: Color(0xFF059669),
  amber: Color(0xFFF59E0B),
  lock: Color(0xFFFFFBEB),
  lockBorder: Color(0xFFFDE68A),
  lockText: Color(0xFF92400E),
  diffAdd: Color(0xFFECFDF5),
  diffAddText: Color(0xFF065F46),
  diffDel: Color(0xFFFEF2F2),
  diffDelText: Color(0xFFBE123C),
  toast: Color(0xFF0F172A),
  shadow: Color(0x1F0F172A),
);

const _dark = _Palette(
  page: Color(0xFF0A0C10),
  bg: Color(0xFF111318),
  sidebar: Color(0xFF15181E),
  card: Color(0xFF1B1F27),
  editorBg: Color(0xFF171A21),
  stage: Color(0xFF0D0F13),
  border: Color(0xFF2B313C),
  slate50: Color(0xFF20252E),
  slate100: Color(0xFF272D37),
  slate400: Color(0xFF6B7585),
  slate500: Color(0xFF8E98A8),
  slate700: Color(0xFFC4CBD6),
  text: Color(0xFFE6E9EF),
  primary: Color(0xFF4C8DFF),
  primaryBg: Color(0xFF18263F),
  primaryBorder: Color(0xFF2D4A7C),
  accent: Color(0xFF34D399),
  amber: Color(0xFFF5B83D),
  lock: Color(0xFF2A2314),
  lockBorder: Color(0xFF5E4A18),
  lockText: Color(0xFFF3C969),
  diffAdd: Color(0xFF0F2A21),
  diffAddText: Color(0xFF6EE7B7),
  diffDel: Color(0xFF2F161B),
  diffDelText: Color(0xFFFDA4AF),
  toast: Color(0xFF2E3440),
  shadow: Color(0x80000000),
);

/// 界面用的颜色。取值时才读当前配色,所以不能放进 const;换配色后整棵树重建(LookSwitcher)。
abstract final class NlColors {
  static _Palette _p = _light;

  static bool get isDark => identical(_p, _dark);
  static void useDark(bool dark) => _p = dark ? _dark : _light;

  static Color get page => _p.page;
  static Color get bg => _p.bg;
  static Color get sidebar => _p.sidebar;
  static Color get card => _p.card;
  static Color get editorBg => _p.editorBg;
  static Color get stage => _p.stage;
  static Color get border => _p.border;
  static Color get slate50 => _p.slate50;
  static Color get slate100 => _p.slate100;
  static Color get slate400 => _p.slate400;
  static Color get slate500 => _p.slate500;
  static Color get slate700 => _p.slate700;
  static Color get text => _p.text;
  static Color get primary => _p.primary;
  static Color get primaryBg => _p.primaryBg;
  static Color get primaryBorder => _p.primaryBorder;
  static Color get accent => _p.accent;
  static Color get amber => _p.amber;
  static Color get lock => _p.lock;
  static Color get lockBorder => _p.lockBorder;
  static Color get lockText => _p.lockText;
  static Color get diffAdd => _p.diffAdd;
  static Color get diffAddText => _p.diffAddText;
  static Color get diffDel => _p.diffDel;
  static Color get diffDelText => _p.diffDelText;
  static Color get toast => _p.toast;
  static Color get shadow => _p.shadow;
}

const latinFont = 'Maple Mono';
const cjkFont = 'LXGW 975 Yuan SC';
const _fallback = [latinFont, cjkFont, 'Microsoft YaHei UI'];

/// 标注正文:等宽,行距宽一点。
TextStyle get monoStyle => TextStyle(fontSize: 12.5, height: 1.6, color: NlColors.slate700);

ThemeData nlTheme() {
  final dark = NlColors.isDark;
  const font = TextStyle(fontFamily: latinFont, fontFamilyFallback: _fallback);
  final scheme = ColorScheme.fromSeed(
    seedColor: NlColors.primary,
    brightness: dark ? Brightness.dark : Brightness.light,
  ).copyWith(
    primary: NlColors.primary,
    surface: NlColors.card,
    surfaceTint: Colors.transparent,
    outline: NlColors.border,
    outlineVariant: NlColors.border,
  );
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: latinFont,
    fontFamilyFallback: _fallback,
    colorScheme: scheme,
    scaffoldBackgroundColor: NlColors.bg,
    dividerColor: NlColors.border,
    splashFactory: NoSplash.splashFactory,
    popupMenuTheme: PopupMenuThemeData(
      color: NlColors.card,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shadowColor: NlColors.shadow,
      menuPadding: const EdgeInsets.all(4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: NlColors.border),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(color: NlColors.toast, borderRadius: BorderRadius.circular(6)),
      textStyle: font.copyWith(fontSize: 11.5, color: Colors.white),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: NlColors.card,
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shadowColor: NlColors.shadow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: NlColors.border),
      ),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: NlColors.primary,
      selectionColor: NlColors.primaryBorder,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(6),
      radius: const Radius.circular(6),
      thumbColor: WidgetStatePropertyAll(NlColors.slate400.withValues(alpha: .5)),
    ),
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: NlColors.text, displayColor: NlColors.text),
  );
}
