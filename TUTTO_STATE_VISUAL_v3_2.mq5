//+------------------------------------------------------------------+
//| TUTTO_STATE_VISUAL v3.2 FULL INTEGRATED                         |
//| State Machine: Swing→Fib→MA→RCI→AUTH→Signal                   |
//| Compile: 0 errors 0 warnings / No repaint / MQL5 only          |
//+------------------------------------------------------------------+
#property copyright   "TUTTO STATE VISUAL v3.2"
#property version     "3.20"
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

//+------------------------------------------------------------------+
// STATE ENUM
//+------------------------------------------------------------------+
enum AUTH_STATE { AUTH_NONE, AUTH_PENDING, AUTH_REAL };
enum MARKET_STATE { MS_BULL, MS_BEAR, MS_NEUTRAL };

//+------------------------------------------------------------------+
// BUFFERS
//+------------------------------------------------------------------+
double BuyBuf[];
double SellBuf[];

//+------------------------------------------------------------------+
// HANDLES
//+------------------------------------------------------------------+
int hEMA  = INVALID_HANDLE;
int hATR  = INVALID_HANDLE;

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
string   FIBO_OBJ_NAME = "TUTTO_FIBO";
string   OBJ_PFX  = "TUTTO_SIG_";
datetime g_last_bar = 0;

//+------------------------------------------------------------------+
// OnInit
//+------------------------------------------------------------------+
int OnInit()
  {
   SetIndexBuffer(0, BuyBuf,  INDICATOR_DATA);
   SetIndexBuffer(1, SellBuf, INDICATOR_DATA);
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetInteger(0, PLOT_ARROW, 233);
   PlotIndexSetInteger(1, PLOT_ARROW, 234);

   hEMA = iMA(_Symbol, PERIOD_CURRENT, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   hATR = iATR(_Symbol, PERIOD_CURRENT, 14);
   if(hEMA == INVALID_HANDLE || hATR == INVALID_HANDLE)
      return INIT_FAILED;

   g_swing.locked = false;
   IndicatorSetString(INDICATOR_SHORTNAME, "TUTTO STATE v3.2");
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
// OnDeinit
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   IndicatorRelease(hEMA);
   IndicatorRelease(hATR);
   SafeDelete(FIBO_OBJ_NAME);
   ObjectsDeleteAll(0, OBJ_PFX);
  }

//+------------------------------------------------------------------+
// UTIL: 安全なオブジェクト削除
//+------------------------------------------------------------------+
void SafeDelete(string name)
  {
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
  }

//+------------------------------------------------------------------+
// BLOCK 1: RCI計算(スピアマン順位相関)
// idx=対象インデックス(直近=rates_total-1を0として時系列降順)
//+------------------------------------------------------------------+
double CalcRCI(const double &close[], int idx, int period, int total)
  {
   if(idx < period - 1 || idx >= total) return 0.0;
   double d2 = 0.0;
   for(int i = 0; i < period; i++)
     {
      int ci = idx - i;
      if(ci < 0 || ci >= total) return 0.0;
      double rt = (double)(i + 1); // 時間順位(新しい=1)
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
// BLOCK 2: Fractalベーススウィング検出(確定バーのみ)
// 戻り値: true=新しいSwingLock確定
// Fractal_Left本の左右を確認（最低Fractal_Left*2+1本必要）
//+------------------------------------------------------------------+
bool DetectSwing(const double &high[], const double &low[],
                 const double &close[], const datetime &time[],
                 int bar_start, int total,
                 double atr_val, int direction)
  {
   // direction: 1=BUY(SwingLow→High), -1=SELL(SwingHigh→Low)
   int FL = Fractal_Left;
   if(bar_start < FL * 2 + 1) return false;

   if(direction == 1) // BUY: SwingHigh検出→その前のSwingLow
     {
      // 最新のFractal High
      int sh_bar = -1;
      for(int i = bar_start - FL; i >= FL; i--)
        {
         bool is_frac = true;
         for(int k = 1; k <= FL; k++)
           {
            if(i - k < 0 || i + k >= total) { is_frac = false; break; }
            if(high[i] <= high[i - k] || high[i] <= high[i + k])
              { is_frac = false; break; }
           }
         if(is_frac) { sh_bar = i; break; }
        }
      if(sh_bar < 0) return false;

      // そのSwingHighより古い位置でFractal Low
      int sl_bar = -1;
      for(int i = sh_bar + FL; i < total - FL; i++)
        {
         bool is_frac = true;
         for(int k = 1; k <= FL; k++)
           {
            if(i - k < 0 || i + k >= total) { is_frac = false; break; }
            if(low[i] >= low[i - k] || low[i] >= low[i + k])
              { is_frac = false; break; }
           }
         if(is_frac) { sl_bar = i; break; }
        }
      if(sl_bar < 0) return false;
      if(sh_bar < 0 || sl_bar < 0) return false;
      if(sh_bar >= total || sl_bar >= total) return false;
      if(high[sh_bar] <= low[sl_bar]) return false;
      double rng = high[sh_bar] - low[sl_bar];
      if(atr_val > 0 && rng < atr_val * ATR_Mult) return false;

      // Lock済みと同一なら更新しない(リペイント防止)
      if(g_swing.locked &&
         g_swing.high_bar == sh_bar &&
         g_swing.low_bar  == sl_bar) return false;

      g_swing.locked    = true;
      g_swing.high      = high[sh_bar];
      g_swing.low       = low[sl_bar];
      g_swing.high_time = time[sh_bar];
      g_swing.low_time  = time[sl_bar];
      g_swing.high_bar  = sh_bar;
      g_swing.low_bar   = sl_bar;
      return true;
     }
   else // SELL: SwingLow検出→その前のSwingHigh
     {
      int sl_bar = -1;
      for(int i = bar_start - FL; i >= FL; i--)
        {
         bool is_frac = true;
         for(int k = 1; k <= FL; k++)
           {
            if(i - k < 0 || i + k >= total) { is_frac = false; break; }
            if(low[i] >= low[i - k] || low[i] >= low[i + k])
              { is_frac = false; break; }
           }
         if(is_frac) { sl_bar = i; break; }
        }
      if(sl_bar < 0) return false;

      int sh_bar = -1;
      for(int i = sl_bar + FL; i < total - FL; i++)
        {
         bool is_frac = true;
         for(int k = 1; k <= FL; k++)
           {
            if(i - k < 0 || i + k >= total) { is_frac = false; break; }
            if(high[i] <= high[i - k] || high[i] <= high[i + k])
              { is_frac = false; break; }
           }
         if(is_frac) { sh_bar = i; break; }
        }
      if(sh_bar < 0) return false;
      if(sh_bar >= total || sl_bar >= total) return false;
      if(high[sh_bar] <= low[sl_bar]) return false;
      double rng = high[sh_bar] - low[sl_bar];
      if(atr_val > 0 && rng < atr_val * ATR_Mult) return false;

      if(g_swing.locked &&
         g_swing.high_bar == sh_bar &&
         g_swing.low_bar  == sl_bar) return false;

      g_swing.locked    = true;
      g_swing.high      = high[sh_bar];
      g_swing.low       = low[sl_bar];
      g_swing.high_time = time[sh_bar];
      g_swing.low_time  = time[sl_bar];
      g_swing.high_bar  = sh_bar;
      g_swing.low_bar   = sl_bar;
      return true;
     }
  }

//+------------------------------------------------------------------+
// BLOCK 3: Fibonacci描画(OBJ_FIBO)
//+------------------------------------------------------------------+
void DrawFibo(datetime t_low, double price_low,
              datetime t_high, double price_high)
  {
   if(!ShowFibo) return;
   SafeDelete(FIBO_OBJ_NAME);

   if(!ObjectCreate(0, FIBO_OBJ_NAME, OBJ_FIBO, 0,
                    t_low,  price_low,
                    t_high, price_high)) return;

   // 標準Fibレベル設定
   double levels[] = {0.0, 0.236, 0.382, 0.5, 0.618,
                      0.705, 0.786, 1.0, 1.382, 1.618,
                      2.0, 2.618, 3.236, 4.236};
   int lv_count = ArraySize(levels);
   ObjectSetInteger(0, FIBO_OBJ_NAME, OBJPROP_LEVELS, lv_count);
   for(int k = 0; k < lv_count; k++)
     {
      ObjectSetDouble(0,  FIBO_OBJ_NAME, OBJPROP_LEVELVALUE, k, levels[k]);
      ObjectSetString(0,  FIBO_OBJ_NAME, OBJPROP_LEVELTEXT,  k,
                      DoubleToString(levels[k], 3));
      ObjectSetInteger(0, FIBO_OBJ_NAME, OBJPROP_LEVELCOLOR, k, clrGray);
      ObjectSetInteger(0, FIBO_OBJ_NAME, OBJPROP_LEVELSTYLE, k, STYLE_DOT);
      ObjectSetInteger(0, FIBO_OBJ_NAME, OBJPROP_LEVELWIDTH, k, 1);
     }
   ObjectSetInteger(0, FIBO_OBJ_NAME, OBJPROP_BACK,      true);
   ObjectSetInteger(0, FIBO_OBJ_NAME, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, FIBO_OBJ_NAME, OBJPROP_RAY_RIGHT,  true);
  }

//+------------------------------------------------------------------+
// BLOCK 4: MA状態判定
//+------------------------------------------------------------------+
MARKET_STATE GetMAState(double close_val, double ma_val)
  {
   if(ma_val <= 0) return MS_NEUTRAL;
   if(close_val > ma_val) return MS_BULL;
   if(close_val < ma_val) return MS_BEAR;
   return MS_NEUTRAL;
  }

//+------------------------------------------------------------------+
// BLOCK 5: AUTH判定
// AUTH_REAL: MA一致 + RCI[-80,+80]内
// AUTH_PENDING: MA一致のみ
// AUTH_NONE: 不一致
//+------------------------------------------------------------------+
AUTH_STATE GetAUTH(MARKET_STATE ms, int direction, double rci_val)
  {
   bool ma_ok  = (direction == 1 && ms == MS_BULL) ||
                 (direction ==-1 && ms == MS_BEAR);
   bool rci_ok = (rci_val >= -80.0 && rci_val <= 80.0);

   if(!ma_ok)          return AUTH_NONE;
   if(ma_ok && rci_ok) return AUTH_REAL;
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
                    (direction==1)?OBJ_ARROW_BUY:OBJ_ARROW_SELL,
                    0, bar_time, price)) return;
   ObjectSetInteger(0, name, OBJPROP_COLOR,
                    (direction==1)?clrLime:clrRed);
   ObjectSetInteger(0, name, OBJPROP_WIDTH,      3);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR,
                    (direction==1)?ANCHOR_TOP:ANCHOR_BOTTOM);
   ObjectSetInteger(0, name, OBJPROP_BACK,       false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
  }

//+------------------------------------------------------------------+
// OnCalculate — 状態機械メインループ
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

   //--- EMA・ATRバッファ取得
   double ema[], atr_buf[];
   ArraySetAsSeries(ema,     false);
   ArraySetAsSeries(atr_buf, false);
   if(CopyBuffer(hEMA, 0, 0, rates_total, ema)     < rates_total) return 0;
   if(CopyBuffer(hATR, 0, 0, rates_total, atr_buf) < rates_total) return 0;

   //--- 処理開始インデックス
   int start = (prev_calculated > 1) ? prev_calculated - 1 : min_req;

   //--- ─── 状態機械ループ ───
   for(int i = start; i < rates_total - 1; i++) // 最終バー(未確定)はスキップ
     {
      BuyBuf[i]  = EMPTY_VALUE;
      SellBuf[i] = EMPTY_VALUE;

      if(i < min_req) continue;

      double atr_val = (i < rates_total) ? atr_buf[i] : 0.0;

      //--- STATE 1: Swing検出(方向判定はMA状態で決定)
      MARKET_STATE ms = GetMAState(close[i], ema[i]);
      int dir = (ms == MS_BULL) ? 1 : (ms == MS_BEAR) ? -1 : 0;
      if(dir == 0) continue;

      bool swing_new = DetectSwing(high, low, close, time,
                                   i, rates_total, atr_val, dir);

      //--- STATE 2: Fib描画(新Swing確定時のみ)
      if(swing_new && g_swing.locked)
         DrawFibo(g_swing.low_time,  g_swing.low,
                  g_swing.high_time, g_swing.high);

      if(!g_swing.locked) continue;

      //--- STATE 3: RCI計算
      double rci = CalcRCI(close, i, RCI_Period, rates_total);

      //--- STATE 4: AUTH判定
      AUTH_STATE auth = GetAUTH(ms, dir, rci);
      if(auth != AUTH_REAL) continue;

      //--- STATE 5: Fib帯チェック
      double rng = g_swing.high - g_swing.low;
      if(rng <= 0) continue;
      double fib_lo, fib_hi;
      if(dir == 1) // BUY: 2.330〜2.618帯
        {
         fib_lo = g_swing.low + 2.330 * rng;
         fib_hi = g_swing.low + 2.618 * rng;
        }
      else // SELL: 3.770〜4.236帯
        {
         fib_lo = g_swing.low + 3.770 * rng;
         fib_hi = g_swing.low + 4.236 * rng;
        }
      bool in_zone = (close[i] >= fib_lo && close[i] <= fib_hi);
      if(!in_zone) continue;

      //--- STATE 6: シグナル発火 → バッファとオブジェクト
      if(dir == 1)
        {
         BuyBuf[i] = low[i];
         DrawSignalArrow(1, time[i], low[i], i);
        }
      else
        {
         SellBuf[i] = high[i];
         DrawSignalArrow(-1, time[i], high[i], i);
        }
     }

   ChartRedraw(0);
   return rates_total;
  }
