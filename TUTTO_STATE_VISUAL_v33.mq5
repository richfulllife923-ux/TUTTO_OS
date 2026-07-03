//+------------------------------------------------------------------+
//| TUTTO_STATE_VISUAL v3.3                                         |
//| State Machine: Swing→Fib→MA→RCI→AUTH→Signal                   |
//| v33変更: STOP=認証帯基準 / TUTTO Fibライン / AUTH ZONE描画      |
//| STATE表示拡張 / OnCalculate構造・AUTH・RCI変更なし              |
//| Compile: 0 errors 0 warnings / No repaint / MQL5 only          |
//+------------------------------------------------------------------+
#property copyright   "TUTTO STATE VISUAL v3.3"
#property version     "3.30"
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   2

#property indicator_label1  "BUY"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrLime
#property indicator_width1  3

#property indicator_label2  "SELL"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrRed
#property indicator_width2  3

//+------------------------------------------------------------------+
// INPUT
//+------------------------------------------------------------------+
input int    EMA_Period   = 200;
input int    RCI_Period   = 25;
input int    Fractal_Left = 2;
input double ATR_Mult     = 1.5;
input bool   ShowFibo     = true;
input bool   ShowAuthZone = true;   // AUTH ZONE矩形表示

//+------------------------------------------------------------------+
// STATE ENUM (変更禁止)
//+------------------------------------------------------------------+
enum AUTH_STATE   { AUTH_NONE, AUTH_PENDING, AUTH_REAL };
enum MARKET_STATE { MS_BULL, MS_BEAR, MS_NEUTRAL };

//+------------------------------------------------------------------+
// BUFFERS
//+------------------------------------------------------------------+
double BuyBuf[];
double SellBuf[];

//+------------------------------------------------------------------+
// HANDLES
//+------------------------------------------------------------------+
int hEMA = INVALID_HANDLE;
int hATR = INVALID_HANDLE;

//+------------------------------------------------------------------+
// SWING LOCK STRUCTURE
//+------------------------------------------------------------------+
struct SwingLock
  {
   bool     locked;
   double   high;
   double   low;
   datetime high_time;
   datetime low_time;
   int      high_bar;
   int      low_bar;
  };

SwingLock g_swing;

//+------------------------------------------------------------------+
// GLOBALS
//+------------------------------------------------------------------+
string   TUTTO_FIBO_NAME = "TUTTO_FIBO";
string   OBJ_PFX         = "TUTTO_SIG_";
datetime g_last_bar      = 0;

//+------------------------------------------------------------------+
// OnInit
//+------------------------------------------------------------------+
int OnInit()
  {
   SetIndexBuffer(0, BuyBuf,  INDICATOR_DATA);
   SetIndexBuffer(1, SellBuf, INDICATOR_DATA);
   PlotIndexSetDouble(0,  PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1,  PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetInteger(0, PLOT_ARROW, 233);
   PlotIndexSetInteger(1, PLOT_ARROW, 234);

   hEMA = iMA(_Symbol, PERIOD_CURRENT, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   hATR = iATR(_Symbol, PERIOD_CURRENT, 14);
   if(hEMA == INVALID_HANDLE || hATR == INVALID_HANDLE)
      return INIT_FAILED;

   g_swing.locked = false;
   g_trend.active = false;
   IndicatorSetString(INDICATOR_SHORTNAME, "TUTTO STATE v3.3");
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
// OnDeinit
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   IndicatorRelease(hEMA);
   IndicatorRelease(hATR);
   SafeDelete(TUTTO_FIBO_NAME);
   ObjectsDeleteAll(0, OBJ_PFX);
  }

//+------------------------------------------------------------------+
// UTIL
//+------------------------------------------------------------------+
void SafeDelete(string name)
  {
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
  }

//+------------------------------------------------------------------+
// BLOCK 1: RCI計算 — 変更禁止
//+------------------------------------------------------------------+
double CalcRCI(const double &close[], int idx, int period, int total)
  {
   if(idx < period - 1 || idx >= total) return 0.0;
   double d2 = 0.0;
   for(int i = 0; i < period; i++)
     {
      int ci = idx - i;
      if(ci < 0 || ci >= total) return 0.0;
      double rt = (double)(i + 1);
      double rp = 1.0;
      for(int j = 0; j < period; j++)
        {
         int cj = idx - j;
         if(cj < 0 || cj >= total) continue;
         if(close[cj] < close[ci]) rp++;
        }
      double d = rt - rp;
      d2 += d * d;
     }
   double n = (double)period;
   return (1.0 - 6.0 * d2 / (n * (n * n - 1.0))) * 100.0;
  }

//+------------------------------------------------------------------+
// BLOCK 2: TUTTO Parent Wave Engine — 親波構造検出
//
// 目的:
//   推進足単位の小波ではなく
//   現在継続しているトレンド波全体を検出する
//
// 思想:
//   BUY: HH/HLが継続する限りFib0（トレンド開始安値）は固定
//        新しいHH確定でFib1（到達点）のみ更新
//        HL崩壊（直近HL割れ）で新しいFib0探索を開始
//
//   SELL: LH/LLが継続する限りFib0（トレンド開始高値）は固定
//         新しいLL確定でFib1のみ更新
//         LH崩壊（直近LH超え）で新しいFib0探索を開始
//
// Fractal定義:
//   SwingHigh: high[i]が前後Fractal_Left本より高い
//   SwingLow:  low[i]が前後Fractal_Left本より低い
//
// リペイント防止:
//   全て確定済みバー（bar_start-1以前）のみ参照
//+------------------------------------------------------------------+

// Fractal SwingHighか判定
bool IsFractalHigh(const double &high[], int i, int total, int fl)
  {
   if(i-fl < 0 || i+fl >= total) return false;
   for(int k = 1; k <= fl; k++)
     {
      if(high[i-k] >= high[i]) return false;
      if(high[i+k] >= high[i]) return false;
     }
   return true;
  }

// Fractal SwingLowか判定
bool IsFractalLow(const double &low[], int i, int total, int fl)
  {
   if(i-fl < 0 || i+fl >= total) return false;
   for(int k = 1; k <= fl; k++)
     {
      if(low[i-k] <= low[i]) return false;
      if(low[i+k] <= low[i]) return false;
     }
   return true;
  }

// トレンド継続状態を保持する構造体（親波の記憶）
struct TrendState
  {
   bool     active;          // トレンド追跡中か
   int      direction;       // 1=BUY(上昇追跡), -1=SELL(下降追跡)
   double   fib0_val;        // Fib0(トレンド開始点)固定値
   int      fib0_bar;
   datetime fib0_time;
   double   last_hl_val;     // BUY: 直近HLの値(崩壊判定用)
   int      last_hl_bar;
   double   last_lh_val;     // SELL: 直近LHの値(崩壊判定用)
   int      last_lh_bar;
   double   fib1_val;        // Fib1(現在の到達点) 継続更新
   int      fib1_bar;
   datetime fib1_time;
  };

TrendState g_trend;

// DetectSwing: 親波構造検出のメインロジック
// 戻り値: true = Fib0/Fib1が更新された(再描画が必要)
bool DetectSwing(const double &high[],
                 const double &low[], const double &close[],
                 const datetime &time[],
                 int bar_start, int total,
                 double atr_val, int direction)
  {
   if(atr_val <= 0) return false;
   int FL = Fractal_Left;
   int req = FL * 4 + 10;
   if(bar_start < req || total < req) return false;

   int search_end = bar_start - 1; // 確定済みバーのみ

   //----------------------------------------------------------
   // CASE A: トレンド追跡中でない、または方向が変わった
   // → Market Structure Shift (BOS) でFib0を探索する
   //
   // BUY-BOS定義:
   //   下降構造中のLL群を遡り、その後ろのLHを
   //   上回るHHが確定した時点が構造転換(BOS)
   //   Fib0 = BOSを生み出した「最後のLL」
   //   Fib1 = BOSの到達点である「HH」
   //----------------------------------------------------------
   if(!g_trend.active || g_trend.direction != direction)
     {
      if(direction == 1) // BUY: BOS検出 (LH超えのHH確定)
        {
         // STEP1: 確定済みバーから新しい方へ走査し
         //        Fractal High群とFractal Low群を時系列に収集
         //        (直近からFL本ずつ遡って判定)
         int    hi_bar[20]; double hi_val[20]; int hi_n = 0;
         int    lo_bar[20]; double lo_val[20]; int lo_n = 0;

         for(int i = search_end - FL; i >= FL && (hi_n < 20 || lo_n < 20); i--)
           {
            if(hi_n < 20 && IsFractalHigh(high, i, total, FL))
              { hi_bar[hi_n] = i; hi_val[hi_n] = high[i]; hi_n++; }
            if(lo_n < 20 && IsFractalLow(low, i, total, FL))
              { lo_bar[lo_n] = i; lo_val[lo_n] = low[i];  lo_n++; }
           }
         // 配列は新しい順(インデックス小=新しい)に格納されている

         if(hi_n < 2 || lo_n < 2) return false;

         // STEP2: 最新のHH(hi_val[0])が、その直前のLH(hi_val[1])を
         //        上回っているかを確認 = BOS成立条件
         //        (hi_val[1]がLH、hi_val[0]がそれを超えたHH)
         bool bos_confirmed = (hi_val[0] > hi_val[1]);
         if(!bos_confirmed) return false;

         double bos_hh_val = hi_val[0];
         int    bos_hh_bar = hi_bar[0];

         // STEP3: Fib0 = BOSのHHより古い側にある「最後のLL」
         //        = bos_hh_barより古い(インデックス大)側で
         //          最初に見つかるFractal Low
         int    fib0_bar = -1;
         double fib0_val = 0;
         for(int k = 0; k < lo_n; k++)
           {
            if(lo_bar[k] > bos_hh_bar) // HHより古い(過去)側
              {
               fib0_bar = lo_bar[k];
               fib0_val = lo_val[k];
               break;
              }
           }
         if(fib0_bar < 0) return false;

         double fib1_val = bos_hh_val;
         int    fib1_bar  = bos_hh_bar;

         if(fib1_val <= fib0_val) return false;
         double rng = fib1_val - fib0_val;
         if(rng <= 0) return false;
         // ATRは補助フィルターのみ(起点判定には使用しない)
         if(atr_val > 0 && rng < atr_val * 0.3) return false;

         // 直近HL: Fib0(LL)とFib1(HH)の間にあるFractal Low
         //         = BOS後の最初の戻り安値の候補(無ければFib0自体)
         double hl_val = fib0_val;
         int    hl_bar = fib0_bar;
         for(int k = 0; k < lo_n; k++)
           {
            if(lo_bar[k] < fib0_bar && lo_bar[k] > fib1_bar)
              {
               if(lo_val[k] > hl_val)
                 { hl_val = lo_val[k]; hl_bar = lo_bar[k]; }
              }
           }

         g_trend.active      = true;
         g_trend.direction   = 1;
         g_trend.fib0_val    = fib0_val;
         g_trend.fib0_bar    = fib0_bar;
         g_trend.fib0_time   = time[fib0_bar];
         g_trend.last_hl_val = hl_val;
         g_trend.last_hl_bar = hl_bar;
         g_trend.fib1_val    = fib1_val;
         g_trend.fib1_bar    = fib1_bar;
         g_trend.fib1_time   = time[fib1_bar];

         g_swing.locked    = true;
         g_swing.high      = fib1_val;
         g_swing.low       = fib0_val;
         g_swing.high_time = time[fib1_bar];
         g_swing.low_time  = time[fib0_bar];
         g_swing.high_bar  = fib1_bar;
         g_swing.low_bar   = fib0_bar;
         return true;
        }
      else // SELL: BOS検出 (HL割れのLL確定)
        {
         int    hi_bar[20]; double hi_val[20]; int hi_n = 0;
         int    lo_bar[20]; double lo_val[20]; int lo_n = 0;

         for(int i = search_end - FL; i >= FL && (hi_n < 20 || lo_n < 20); i--)
           {
            if(hi_n < 20 && IsFractalHigh(high, i, total, FL))
              { hi_bar[hi_n] = i; hi_val[hi_n] = high[i]; hi_n++; }
            if(lo_n < 20 && IsFractalLow(low, i, total, FL))
              { lo_bar[lo_n] = i; lo_val[lo_n] = low[i];  lo_n++; }
           }

         if(hi_n < 2 || lo_n < 2) return false;

         // 最新のLL(lo_val[0])が直前のHL(lo_val[1])を下回るか = BOS
         bool bos_confirmed = (lo_val[0] < lo_val[1]);
         if(!bos_confirmed) return false;

         double bos_ll_val = lo_val[0];
         int    bos_ll_bar = lo_bar[0];

         // Fib0 = BOSのLLより古い側にある「最後のHH」
         int    fib0_bar = -1;
         double fib0_val = 0;
         for(int k = 0; k < hi_n; k++)
           {
            if(hi_bar[k] > bos_ll_bar)
              {
               fib0_bar = hi_bar[k];
               fib0_val = hi_val[k];
               break;
              }
           }
         if(fib0_bar < 0) return false;

         double fib1_val = bos_ll_val;
         int    fib1_bar  = bos_ll_bar;

         if(fib1_val >= fib0_val) return false;
         double rng = fib0_val - fib1_val;
         if(rng <= 0) return false;
         if(atr_val > 0 && rng < atr_val * 0.3) return false;

         // 直近LH: Fib0(HH)とFib1(LL)の間にあるFractal High
         double lh_val = fib0_val;
         int    lh_bar = fib0_bar;
         for(int k = 0; k < hi_n; k++)
           {
            if(hi_bar[k] < fib0_bar && hi_bar[k] > fib1_bar)
              {
               if(hi_val[k] < lh_val)
                 { lh_val = hi_val[k]; lh_bar = hi_bar[k]; }
              }
           }

         g_trend.active      = true;
         g_trend.direction   = -1;
         g_trend.fib0_val    = fib0_val;
         g_trend.fib0_bar    = fib0_bar;
         g_trend.fib0_time   = time[fib0_bar];
         g_trend.last_lh_val = lh_val;
         g_trend.last_lh_bar = lh_bar;
         g_trend.fib1_val    = fib1_val;
         g_trend.fib1_bar    = fib1_bar;
         g_trend.fib1_time   = time[fib1_bar];

         g_swing.locked    = true;
         g_swing.high      = fib0_val;
         g_swing.low       = fib1_val;
         g_swing.high_time = time[fib0_bar];
         g_swing.low_time  = time[fib1_bar];
         g_swing.high_bar  = fib0_bar;
         g_swing.low_bar   = fib1_bar;
         return true;
        }
     }

   //----------------------------------------------------------
   // CASE B: 同方向でトレンド追跡中
   // → HL/LH崩壊チェック → 継続ならFib1更新を試みる
   //----------------------------------------------------------
   bool updated = false;

   if(direction == 1) // BUY追跡中
     {
      // 崩壊チェック: 直近確定バーがlast_hl_valを下回ったか
      for(int i = g_trend.last_hl_bar - 1; i >= 0 && i >= search_end - 5; i--)
        {
         if(i > search_end) continue;
         if(close[i] < g_trend.last_hl_val)
           {
            // HL崩壊 → トレンド終了 → 追跡解除
            g_trend.active = false;
            return false; // 次回呼び出しでCASE Aに入る
           }
        }

      // 新しいFractal Highが確定していればFib1を更新(伸ばす)
      int new_fib1_bar = -1;
      double new_fib1_val = g_trend.fib1_val;
      for(int i = search_end - FL; i > g_trend.fib1_bar; i--)
        {
         if(IsFractalHigh(high, i, total, FL) && high[i] > new_fib1_val)
           {
            new_fib1_bar = i;
            new_fib1_val = high[i];
           }
        }
      if(new_fib1_bar > 0)
        {
         g_trend.fib1_val  = new_fib1_val;
         g_trend.fib1_bar  = new_fib1_bar;
         g_trend.fib1_time = time[new_fib1_bar];

         g_swing.high      = new_fib1_val;
         g_swing.high_time = time[new_fib1_bar];
         g_swing.high_bar  = new_fib1_bar;
         updated = true;
        }

      // 新しいFractal Lowが直近HLより高ければHLを更新(トレンド健全性維持)
      for(int i = search_end - FL; i > g_trend.last_hl_bar; i--)
        {
         if(IsFractalLow(low, i, total, FL) && low[i] > g_trend.last_hl_val)
           {
            g_trend.last_hl_val = low[i];
            g_trend.last_hl_bar = i;
           }
        }
     }
   else // SELL追跡中
     {
      for(int i = g_trend.last_lh_bar - 1; i >= 0 && i >= search_end - 5; i--)
        {
         if(i > search_end) continue;
         if(close[i] > g_trend.last_lh_val)
           {
            g_trend.active = false;
            return false;
           }
        }

      int new_fib1_bar = -1;
      double new_fib1_val = g_trend.fib1_val;
      for(int i = search_end - FL; i > g_trend.fib1_bar; i--)
        {
         if(IsFractalLow(low, i, total, FL) && low[i] < new_fib1_val)
           {
            new_fib1_bar = i;
            new_fib1_val = low[i];
           }
        }
      if(new_fib1_bar > 0)
        {
         g_trend.fib1_val  = new_fib1_val;
         g_trend.fib1_bar  = new_fib1_bar;
         g_trend.fib1_time = time[new_fib1_bar];

         g_swing.low       = new_fib1_val;
         g_swing.low_time  = time[new_fib1_bar];
         g_swing.low_bar   = new_fib1_bar;
         updated = true;
        }

      for(int i = search_end - FL; i > g_trend.last_lh_bar; i--)
        {
         if(IsFractalHigh(high, i, total, FL) && high[i] < g_trend.last_lh_val)
           {
            g_trend.last_lh_val = high[i];
            g_trend.last_lh_bar = i;
           }
        }
     }

   return updated;
  }

//+------------------------------------------------------------------+
// BLOCK 3: Fibonacci描画
//+------------------------------------------------------------------+
void DrawFibo(datetime t_low, double price_low,
              datetime t_high, double price_high)
  {
   if(!ShowFibo) return;
   SafeDelete(TUTTO_FIBO_NAME);
   if(!ObjectCreate(0, TUTTO_FIBO_NAME, OBJ_FIBO, 0,
                    t_low, price_low, t_high, price_high)) return;

   double levels[] = {0.0, 0.236, 0.382, 0.5, 0.618,
                      0.705, 0.786, 1.0, 1.382, 1.618,
                      2.0, 2.618, 3.236, 4.236};
   int lv_count = ArraySize(levels);
   ObjectSetInteger(0, TUTTO_FIBO_NAME, OBJPROP_LEVELS, (long)lv_count);
   for(int k = 0; k < lv_count; k++)
     {
      ObjectSetDouble (0, TUTTO_FIBO_NAME, OBJPROP_LEVELVALUE, k, levels[k]);
      ObjectSetString (0, TUTTO_FIBO_NAME, OBJPROP_LEVELTEXT,  k,
                       DoubleToString(levels[k], 3));
      ObjectSetInteger(0, TUTTO_FIBO_NAME, OBJPROP_LEVELCOLOR, k, (long)clrGray);
      ObjectSetInteger(0, TUTTO_FIBO_NAME, OBJPROP_LEVELSTYLE, k, (long)STYLE_DOT);
      ObjectSetInteger(0, TUTTO_FIBO_NAME, OBJPROP_LEVELWIDTH, k, 1L);
     }
   ObjectSetInteger(0, TUTTO_FIBO_NAME, OBJPROP_BACK,       true);
   ObjectSetInteger(0, TUTTO_FIBO_NAME, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, TUTTO_FIBO_NAME, OBJPROP_RAY_RIGHT,  true);
  }

//+------------------------------------------------------------------+
// BLOCK 4: MA状態判定 — 変更禁止
//+------------------------------------------------------------------+
MARKET_STATE GetMAState(double close_val, double ma_val)
  {
   if(ma_val <= 0)         return MS_NEUTRAL;
   if(close_val > ma_val)  return MS_BULL;
   if(close_val < ma_val)  return MS_BEAR;
   return MS_NEUTRAL;
  }

//+------------------------------------------------------------------+
// BLOCK 5: AUTH判定 — 変更禁止
//+------------------------------------------------------------------+
AUTH_STATE GetAUTH(MARKET_STATE ms, int direction, double rci_val)
  {
   bool ma_ok  = (direction ==  1 && ms == MS_BULL) ||
                 (direction == -1 && ms == MS_BEAR);
   bool rci_ok = (rci_val >= -80.0 && rci_val <= 80.0);
   if(!ma_ok)           return AUTH_NONE;
   if(ma_ok && rci_ok)  return AUTH_REAL;
   return AUTH_PENDING;
  }

//+------------------------------------------------------------------+
// BLOCK 6: シグナル矢印描画
//+------------------------------------------------------------------+
void DrawSignalArrow(int direction, datetime bar_time,
                     double price, int bar_idx)
  {
   string name = OBJ_PFX + (direction==1?"BUY":"SELL") +
                 IntegerToString(bar_idx);
   SafeDelete(name);
   if(!ObjectCreate(0, name,
                    (direction==1) ? OBJ_ARROW_BUY : OBJ_ARROW_SELL,
                    0, bar_time, price)) return;
   ObjectSetInteger(0, name, OBJPROP_COLOR,
                    (direction==1) ? clrLime : clrRed);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,      3);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR,
                    (direction==1) ? ANCHOR_TOP : ANCHOR_BOTTOM);
   ObjectSetInteger(0, name, OBJPROP_BACK,       false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
  }

//+------------------------------------------------------------------+
// UI: 水平ライン描画
//+------------------------------------------------------------------+
void DrawHLine(string name, double price, color clr,
               int width, ENUM_LINE_STYLE style, string lbl)
  {
   SafeDelete(name);
   SafeDelete(name+"_L");
   if(!ObjectCreate(0, name, OBJ_HLINE, 0, 0, price)) return;
   ObjectSetInteger(0, name, OBJPROP_COLOR,     clr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,     width);
   ObjectSetInteger(0, name, OBJPROP_STYLE,     style);
   ObjectSetInteger(0, name, OBJPROP_BACK,      false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE,false);
   if(lbl == "") return;
   datetime t0 = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(!ObjectCreate(0, name+"_L", OBJ_TEXT, 0, t0, price)) return;
   ObjectSetString (0, name+"_L", OBJPROP_TEXT,      lbl);
   ObjectSetInteger(0, name+"_L", OBJPROP_COLOR,     clr);
   ObjectSetInteger(0, name+"_L", OBJPROP_FONTSIZE,  11);
   ObjectSetString (0, name+"_L", OBJPROP_FONT,      "Arial Black");
   ObjectSetInteger(0, name+"_L", OBJPROP_ANCHOR,    ANCHOR_LEFT_LOWER);
   ObjectSetInteger(0, name+"_L", OBJPROP_BACK,      false);
   ObjectSetInteger(0, name+"_L", OBJPROP_SELECTABLE,false);
  }

//+------------------------------------------------------------------+
// UI: AUTH ZONE矩形描画 (半透明背景)
//+------------------------------------------------------------------+
void DrawAuthZone(string name, datetime t_start,
                  double zl, double zh, color clr)
  {
   if(!ShowAuthZone) return;
   SafeDelete(name);
   // 右端を現在バーから100本先まで延長
   datetime t_end = iTime(_Symbol, PERIOD_CURRENT, 0) +
                    (long)PeriodSeconds(PERIOD_CURRENT) * 100;
   if(!ObjectCreate(0, name, OBJ_RECTANGLE, 0,
                    t_start, zh, t_end, zl)) return;
   ObjectSetInteger(0, name, OBJPROP_COLOR,     clr);
   ObjectSetInteger(0, name, OBJPROP_FILL,      true);
   ObjectSetInteger(0, name, OBJPROP_BACK,      true);   // 背面配置
   ObjectSetInteger(0, name, OBJPROP_WIDTH,     1);
   ObjectSetInteger(0, name, OBJPROP_STYLE,     STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE,false);
  }

//+------------------------------------------------------------------+
// UI: 状態ラベル(左上)
//+------------------------------------------------------------------+
void DrawStateLabel(string txt, color clr)
  {
   string name = OBJ_PFX+"STATE";
   if(ObjectFind(0,name) < 0) ObjectCreate(0,name,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE, 10);
   ObjectSetString (0,name,OBJPROP_TEXT,      txt);
   ObjectSetInteger(0,name,OBJPROP_COLOR,     clr);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,  18);
   ObjectSetString (0,name,OBJPROP_FONT,      "Arial Black");
   ObjectSetInteger(0,name,OBJPROP_BACK,      false);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
  }

//+------------------------------------------------------------------+
// UI: サブ状態ラベル(左上・2行目)
//+------------------------------------------------------------------+
void DrawSubLabel(string txt, color clr)
  {
   string name = OBJ_PFX+"SUBLBL";
   if(ObjectFind(0,name) < 0) ObjectCreate(0,name,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,name,OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE, 38);  // 1行目の下
   ObjectSetString (0,name,OBJPROP_TEXT,      txt);
   ObjectSetInteger(0,name,OBJPROP_COLOR,     clr);
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,  12);
   ObjectSetString (0,name,OBJPROP_FONT,      "Arial Bold");
   ObjectSetInteger(0,name,OBJPROP_BACK,      false);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
  }

//+------------------------------------------------------------------+
// UI: 全オブジェクト削除
//+------------------------------------------------------------------+
void DeleteAllUI()
  {
   // UIオブジェクト名リスト
   string keys[] =
     {
      "ENTRY","ENTRY_L",
      "STOP", "STOP_L",
      "LV233","LV233_L",
      "LV261","LV261_L",
      "TP1",  "TP1_L",
      "TP2",  "TP2_L",
      "TP3",  "TP3_L",
      "AUTH_ZONE",
      "BIG_LBL",
      "STATE","SUBLBL"
     };
   for(int k = 0; k < ArraySize(keys); k++)
      SafeDelete(OBJ_PFX + keys[k]);
  }

//+------------------------------------------------------------------+
// UI MAIN: TUTTO Fib準拠の全ライン描画
// 修正1: STOP = 認証帯基準
// 修正2: LV233/LV261/TP1/TP2/TP3 = TUTTO Fib水準
// 修正3: AUTH ZONE矩形(2.330〜2.618)
//+------------------------------------------------------------------+
void DrawTradeUI(int dir, datetime sig_time, datetime swing_time,
                 double entry,
                 double sw_low, double sw_high, double rng)
  {
   DeleteAllUI();

   if(rng <= 0) return;

   if(dir == 1) // ===== BUY =====
     {
      // TUTTO Fib水準 (base = sw_low = 0)
      double lv233 = sw_low + 2.330 * rng;  // 認証帯下限
      double lv261 = sw_low + 2.618 * rng;  // 認証帯上限 = STOP基準
      double tp1   = sw_low + 3.236 * rng;  // TP1
      double tp2   = sw_low + 4.236 * rng;  // TP2
      double tp3   = sw_low + 6.854 * rng;  // TP3
      double stop  = lv261;                  // STOP = 認証帯上限(BUY帯を割ったら終了)

      // AUTH ZONE矩形 (2.330〜2.618 / Lime半透明)
      DrawAuthZone(OBJ_PFX+"AUTH_ZONE", swing_time,
                   lv233, lv261, C'0,80,0');

      // Fibレベルライン
      DrawHLine(OBJ_PFX+"LV233", lv233, clrLime,         1, STYLE_DOT,
                "  2.330  AUTH ZONE LOW  "+DoubleToString(lv233,_Digits));
      DrawHLine(OBJ_PFX+"LV261", lv261, clrLime,         2, STYLE_SOLID,
                "  2.618  AUTH ZONE HIGH "+DoubleToString(lv261,_Digits));
      DrawHLine(OBJ_PFX+"TP1",   tp1,   clrDodgerBlue,   2, STYLE_SOLID,
                "  TP1  3.236  "+DoubleToString(tp1,_Digits));
      DrawHLine(OBJ_PFX+"TP2",   tp2,   clrMediumOrchid, 2, STYLE_SOLID,
                "  TP2  4.236  "+DoubleToString(tp2,_Digits));
      DrawHLine(OBJ_PFX+"TP3",   tp3,   clrGold,         2, STYLE_SOLID,
                "  TP3  6.854  "+DoubleToString(tp3,_Digits));

      // ENTRY / STOP
      DrawHLine(OBJ_PFX+"ENTRY", entry, clrWhite,   2, STYLE_SOLID,
                "  ENTRY  "+DoubleToString(entry,_Digits));
      DrawHLine(OBJ_PFX+"STOP",  stop,  clrDarkRed, 3, STYLE_SOLID,
                "  STOP  2.618  "+DoubleToString(stop,_Digits));

      // 状態表示
      DrawStateLabel("▲ REAL BUY", clrLime);
      DrawSubLabel("ZONE BUY  AUTH REAL", clrAqua);
     }
   else // ===== SELL =====
     {
      // TUTTO Fib水準 (base = sw_high = 0、下方拡張)
      double lv233 = sw_high - 2.330 * rng;  // 認証帯上限
      double lv261 = sw_high - 2.618 * rng;  // 認証帯下限 = STOP基準
      double tp1   = sw_high - 3.236 * rng;  // TP1
      double tp2   = sw_high - 4.236 * rng;  // TP2
      double tp3   = sw_high - 6.854 * rng;  // TP3
      double stop  = lv261;                   // STOP = 認証帯下限(SELL帯を抜けたら終了)

      // AUTH ZONE矩形 (lv261〜lv233 / Red半透明)
      DrawAuthZone(OBJ_PFX+"AUTH_ZONE", swing_time,
                   lv261, lv233, C'100,0,0');

      // Fibレベルライン
      DrawHLine(OBJ_PFX+"LV233", lv233, clrRed,          1, STYLE_DOT,
                "  2.330  AUTH ZONE HIGH "+DoubleToString(lv233,_Digits));
      DrawHLine(OBJ_PFX+"LV261", lv261, clrRed,           2, STYLE_SOLID,
                "  2.618  AUTH ZONE LOW  "+DoubleToString(lv261,_Digits));
      DrawHLine(OBJ_PFX+"TP1",   tp1,   clrDodgerBlue,   2, STYLE_SOLID,
                "  TP1  3.236  "+DoubleToString(tp1,_Digits));
      DrawHLine(OBJ_PFX+"TP2",   tp2,   clrMediumOrchid, 2, STYLE_SOLID,
                "  TP2  4.236  "+DoubleToString(tp2,_Digits));
      DrawHLine(OBJ_PFX+"TP3",   tp3,   clrGold,         2, STYLE_SOLID,
                "  TP3  6.854  "+DoubleToString(tp3,_Digits));

      // ENTRY / STOP
      DrawHLine(OBJ_PFX+"ENTRY", entry, clrWhite,   2, STYLE_SOLID,
                "  ENTRY  "+DoubleToString(entry,_Digits));
      DrawHLine(OBJ_PFX+"STOP",  stop,  clrDarkRed, 3, STYLE_SOLID,
                "  STOP  2.618  "+DoubleToString(stop,_Digits));

      // 状態表示
      DrawStateLabel("▼ REAL SELL", clrRed);
      DrawSubLabel("ZONE SELL  AUTH REAL", clrOrange);
     }
  }

//+------------------------------------------------------------------+
// OnCalculate — 状態機械メインループ (変更禁止)
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double   &open[],
                const double   &high[],
                const double   &low[],
                const double   &close[],
                const long     &tick_volume[],
                const long     &volume[],
                const int      &spread[])
  {
   int min_req = EMA_Period + RCI_Period + Fractal_Left * 4 + 10;
   if(rates_total < min_req) return 0;

   double ema[], atr_buf[];
   ArraySetAsSeries(ema,     false);
   ArraySetAsSeries(atr_buf, false);
   if(CopyBuffer(hEMA, 0, 0, rates_total, ema)     < rates_total) return 0;
   if(CopyBuffer(hATR, 0, 0, rates_total, atr_buf) < rates_total) return 0;

   int start = (prev_calculated > 1) ? prev_calculated - 1 : min_req;

   for(int i = start; i < rates_total - 1; i++)
     {
      BuyBuf[i]  = EMPTY_VALUE;
      SellBuf[i] = EMPTY_VALUE;

      if(i < min_req) continue;

      double atr_val = atr_buf[i];

      //--- STATE 1: MA状態 → 方向決定 (変更禁止)
      MARKET_STATE ms  = GetMAState(close[i], ema[i]);
      int          dir = (ms == MS_BULL) ? 1 : (ms == MS_BEAR) ? -1 : 0;
      if(dir == 0) continue;

      //--- STATE 2: Swing検出 (変更禁止)
      bool swing_new = DetectSwing(high, low, close, time,
                                   i, rates_total, atr_val, dir);
      if(swing_new && g_swing.locked)
         DrawFibo(g_swing.low_time,  g_swing.low,
                  g_swing.high_time, g_swing.high);

      if(!g_swing.locked) continue;

      //--- STATE 3: RCI計算 (変更禁止)
      double rci = CalcRCI(close, i, RCI_Period, rates_total);

      //--- STATE 4: AUTH判定 (変更禁止)
      AUTH_STATE auth = GetAUTH(ms, dir, rci);
      if(auth != AUTH_REAL)
        {
         // 最終確定バーでのみ状態ラベル更新
         if(i == rates_total - 2)
           {
            if(auth == AUTH_PENDING)
              {
               DrawStateLabel("◎ WAIT", clrYellow);
               DrawSubLabel(dir==1 ? "AUTH BUY  WAIT" : "AUTH SELL  WAIT",
                            clrYellow);
              }
            else
              {
               DrawStateLabel("✕ FAKE", clrGray);
               DrawSubLabel("EXIT ZONE", clrGray);
              }
           }
         continue;
        }

      //--- STATE 5: Fib帯チェック (変更禁止)
      double rng    = g_swing.high - g_swing.low;
      if(rng <= 0) continue;
      double fib_lo, fib_hi;
      if(dir == 1)
        {
         fib_lo = g_swing.low + 2.330 * rng;
         fib_hi = g_swing.low + 2.618 * rng;
        }
      else
        {
         fib_lo = g_swing.low + 3.770 * rng;
         fib_hi = g_swing.low + 4.236 * rng;
        }
      bool in_zone = (close[i] >= fib_lo && close[i] <= fib_hi);

      // ゾーン到達前の状態表示(最終バーのみ)
      if(!in_zone)
        {
         if(i == rates_total - 2)
           {
            if(dir == 1)
              { DrawStateLabel("◎ AUTH BUY", clrLime);
                DrawSubLabel("ZONE BUY  WAIT", clrAqua); }
            else
              { DrawStateLabel("◎ AUTH SELL", clrRed);
                DrawSubLabel("ZONE SELL  WAIT", clrOrange); }
           }
         continue;
        }

      //--- STATE 6: シグナル発火 (変更禁止) + UI描画(v33修正)
      datetime swing_anchor = (dir==1) ? g_swing.low_time : g_swing.high_time;

      if(dir == 1)
        {
         BuyBuf[i] = low[i];
         DrawSignalArrow(1, time[i], low[i], i);
         DrawTradeUI(1, time[i], swing_anchor,
                     close[i], g_swing.low, g_swing.high, rng);
        }
      else
        {
         SellBuf[i] = high[i];
         DrawSignalArrow(-1, time[i], high[i], i);
         DrawTradeUI(-1, time[i], swing_anchor,
                     close[i], g_swing.low, g_swing.high, rng);
        }
     }

   ChartRedraw(0);
   return rates_total;
  }
