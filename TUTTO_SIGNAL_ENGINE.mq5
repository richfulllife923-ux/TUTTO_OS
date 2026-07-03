//+------------------------------------------------------------------+
//| TUTTO_SIGNAL_ENGINE.mq5                                          |
//| Project B: Signal Engine — UI layer refactor (v1.00 -> v1.1)     |
//|                                                                   |
//| LOGIC UNCHANGED: GetSwing, FibScore, MAScore, StructureScore,     |
//| RiskScore, CalcTotalScore, DirectionFromCloseMA, CalcHeatmapBias, |
//| CalcRCI, DrawSignalArrow(score routing), and the entire           |
//| OnCalculate loop/thresholds are byte-identical to v1.00.          |
//|                                                                   |
//| CHANGED (visualization only):                                     |
//|  - DrawHeatmapPanel() + the second Comment() block -> one shared  |
//|    corner panel call (TuttoPanel_Show), no duplicated text        |
//|  - DrawTPSLLines()/DeleteTPSLLines() (raw OBJ_HLINE, prone to      |
//|    overlapping price-tags) -> TuttoLevels_Draw() with automatic    |
//|    label collision avoidance                                      |
//| Auto-trading remains disabled (no OrderSend). Confirmed bars only,|
//| no repaint — unchanged.                                            |
//+------------------------------------------------------------------+
#property copyright   "TUTTO SIGNAL ENGINE — Project B"
#property version     "1.10"
#property indicator_chart_window
#property indicator_buffers 3
#property indicator_plots   3

//+------------------------------------------------------------------+
// BUFFERS (unchanged)
//+------------------------------------------------------------------+
double StrongArrowBuf[];
double MidArrowBuf[];
double WeakArrowBuf[];

#property indicator_label1  "Strong"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrDodgerBlue
#property indicator_width1  3

#property indicator_label2  "Mid"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrWhite
#property indicator_width2  2

#property indicator_label3  "Weak"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrSilver
#property indicator_width3  1

#include <TUTTO/TUTTO_UI_ObjectManager.mqh>
#include <TUTTO/TUTTO_UI_Panel.mqh>
#include <TUTTO/TUTTO_UI_Levels.mqh>
#include <TUTTO/TUTTO_UI_Style.mqh>

//+------------------------------------------------------------------+
// INPUT (unchanged)
//+------------------------------------------------------------------+
input int    MA_Period         = 200;
input int    Lookback_Bars     = 80;
input int    Swing_Lookback    = 20;
input double Score_Strong_Th   = 80.0;
input double Score_Mid_Th      = 60.0;
input double Score_Weak_Th     = 40.0;

input bool   ShowHeatmap       = true;
input bool   ShowTPSL          = true;
input int    RCI_Period        = 9;

//+------------------------------------------------------------------+
// globals (unchanged, plus one UI object manager)
//+------------------------------------------------------------------+
int      hEMA          = INVALID_HANDLE;
int      hEMA_W1        = INVALID_HANDLE;
int      hEMA_D1        = INVALID_HANDLE;
int      hEMA_H4        = INVALID_HANDLE;
int      hEMA_H1        = INVALID_HANDLE;
int      hEMA_M15       = INVALID_HANDLE;
int      hEMA_M5        = INVALID_HANDLE;

datetime g_last_bar      = 0;

CTuttoObjectManager g_mgr;

//+------------------------------------------------------------------+
// OnInit
//+------------------------------------------------------------------+
int OnInit()
  {
   SetIndexBuffer(0, StrongArrowBuf, INDICATOR_DATA);
   SetIndexBuffer(1, MidArrowBuf,    INDICATOR_DATA);
   SetIndexBuffer(2, WeakArrowBuf,   INDICATOR_DATA);

   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   PlotIndexSetInteger(0, PLOT_ARROW, 233);
   PlotIndexSetInteger(1, PLOT_ARROW, 233);
   PlotIndexSetInteger(2, PLOT_ARROW, 233);

   hEMA = iMA(_Symbol, PERIOD_CURRENT, MA_Period, 0, MODE_EMA, PRICE_CLOSE);
   if(hEMA == INVALID_HANDLE) return INIT_FAILED;

   if(ShowHeatmap)
     {
      hEMA_W1  = iMA(_Symbol, PERIOD_W1,  MA_Period, 0, MODE_EMA, PRICE_CLOSE);
      hEMA_D1  = iMA(_Symbol, PERIOD_D1,  MA_Period, 0, MODE_EMA, PRICE_CLOSE);
      hEMA_H4  = iMA(_Symbol, PERIOD_H4,  MA_Period, 0, MODE_EMA, PRICE_CLOSE);
      hEMA_H1  = iMA(_Symbol, PERIOD_H1,  MA_Period, 0, MODE_EMA, PRICE_CLOSE);
      hEMA_M15 = iMA(_Symbol, PERIOD_M15, MA_Period, 0, MODE_EMA, PRICE_CLOSE);
      hEMA_M5  = iMA(_Symbol, PERIOD_M5,  MA_Period, 0, MODE_EMA, PRICE_CLOSE);

      if(hEMA_W1==INVALID_HANDLE || hEMA_D1==INVALID_HANDLE || hEMA_H4==INVALID_HANDLE ||
         hEMA_H1==INVALID_HANDLE || hEMA_M15==INVALID_HANDLE || hEMA_M5==INVALID_HANDLE)
         return INIT_FAILED;
     }

   g_last_bar = 0;
   g_mgr.Init("SIGNAL");
   IndicatorSetString(INDICATOR_SHORTNAME, "TUTTO SIGNAL ENGINE (Project B)");
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
// OnDeinit
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(hEMA      != INVALID_HANDLE) IndicatorRelease(hEMA);
   if(hEMA_W1   != INVALID_HANDLE) IndicatorRelease(hEMA_W1);
   if(hEMA_D1   != INVALID_HANDLE) IndicatorRelease(hEMA_D1);
   if(hEMA_H4   != INVALID_HANDLE) IndicatorRelease(hEMA_H4);
   if(hEMA_H1   != INVALID_HANDLE) IndicatorRelease(hEMA_H1);
   if(hEMA_M15  != INVALID_HANDLE) IndicatorRelease(hEMA_M15);
   if(hEMA_M5   != INVALID_HANDLE) IndicatorRelease(hEMA_M5);
   g_mgr.DeleteAll();
  }

//+------------------------------------------------------------------+
// ── LIGHT MODE: swing detection (unchanged) ──
//+------------------------------------------------------------------+
void GetSwing(const double &high[], const double &low[], int idx,
             double &sw_high, double &sw_low)
  {
   sw_high = 0; sw_low = DBL_MAX;
   int start = idx - Swing_Lookback;
   if(start < 0) start = 0;
   for(int i = start; i < idx; i++)
     {
      if(high[i] > sw_high) sw_high = high[i];
      if(low[i]  < sw_low)  sw_low  = low[i];
     }
  }

//+------------------------------------------------------------------+
// ── LIGHT MODE: FibScore (unchanged) ──
//+------------------------------------------------------------------+
double FibScore(double price, double sw_high, double sw_low)
  {
   double range = sw_high - sw_low;
   if(range <= 0) return 0;
   double retrace = (sw_high - price) / range;

   if(retrace <= 0.618 && retrace >= 0.5) return 30;
   if(retrace < 0.5 && retrace >= 0.382)  return 20;
   return 10;
  }

//+------------------------------------------------------------------+
// ── LIGHT MODE: MAScore (unchanged) ──
//+------------------------------------------------------------------+
double MAScore(double price, double ma)
  {
   if(ma <= 0) return 5;
   if(price > ma) return 25;
   if(MathAbs(price - ma) / ma < 0.002) return 15;
   return 5;
  }

//+------------------------------------------------------------------+
// ── LIGHT MODE: StructureScore (unchanged) ──
//+------------------------------------------------------------------+
double StructureScore(double close_val, double prev_high, double prev_low)
  {
   if(close_val > prev_high) return 25;
   if(close_val > prev_low)  return 15;
   return 10;
  }

//+------------------------------------------------------------------+
// ── LIGHT MODE: RiskScore (unchanged) ──
//+------------------------------------------------------------------+
double RiskScore(double price, double sw_low)
  {
   double dist = price - sw_low;
   double pt = _Point;
   if(pt <= 0) pt = 0.00001;
   if(dist > 50 * pt) return 20;
   if(dist > 20 * pt) return 10;
   return 5;
  }

//+------------------------------------------------------------------+
// ── lightweight RCI (FULL MODE only) (unchanged) ──
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
      d2 += d*d;
     }
   double n = (double)period;
   return (1.0 - 6.0*d2/(n*(n*n-1.0))) * 100.0;
  }

//+------------------------------------------------------------------+
// ── total score (unchanged) ──
//+------------------------------------------------------------------+
double CalcTotalScore(double price, double sw_high, double sw_low, double ma,
                      double prev_high, double prev_low)
  {
   double s = FibScore(price, sw_high, sw_low) +
              MAScore(price, ma) +
              StructureScore(price, prev_high, prev_low) +
              RiskScore(price, sw_low);
   return s;
  }

//+------------------------------------------------------------------+
// ── direction from close vs MA (unchanged) ──
//+------------------------------------------------------------------+
double DirectionFromCloseMA(double close_val, double ma_val)
  {
   if(ma_val <= 0) return 0;
   double diff_pct = (close_val - ma_val) / ma_val;
   if(diff_pct > 0.0005)  return 1.0;
   if(diff_pct < -0.0005) return -1.0;
   return 0.0;
  }

//+------------------------------------------------------------------+
// ── MTF Heatmap Bias (unchanged) ──
//+------------------------------------------------------------------+
double CalcHeatmapBias()
  {
   if(!ShowHeatmap) return 0;

   double close_w1=0, close_d1=0, close_h4=0, close_h1=0, close_m15=0, close_m5=0;
   double ma_w1=0, ma_d1=0, ma_h4=0, ma_h1=0, ma_m15=0, ma_m5=0;

   double cb[1], mb[1];

   if(CopyClose(_Symbol, PERIOD_W1, 1, 1, cb) > 0) close_w1 = cb[0];
   if(CopyBuffer(hEMA_W1, 0, 1, 1, mb) > 0) ma_w1 = mb[0];

   if(CopyClose(_Symbol, PERIOD_D1, 1, 1, cb) > 0) close_d1 = cb[0];
   if(CopyBuffer(hEMA_D1, 0, 1, 1, mb) > 0) ma_d1 = mb[0];

   if(CopyClose(_Symbol, PERIOD_H4, 1, 1, cb) > 0) close_h4 = cb[0];
   if(CopyBuffer(hEMA_H4, 0, 1, 1, mb) > 0) ma_h4 = mb[0];

   if(CopyClose(_Symbol, PERIOD_H1, 1, 1, cb) > 0) close_h1 = cb[0];
   if(CopyBuffer(hEMA_H1, 0, 1, 1, mb) > 0) ma_h1 = mb[0];

   if(CopyClose(_Symbol, PERIOD_M15, 1, 1, cb) > 0) close_m15 = cb[0];
   if(CopyBuffer(hEMA_M15, 0, 1, 1, mb) > 0) ma_m15 = mb[0];

   if(CopyClose(_Symbol, PERIOD_M5, 1, 1, cb) > 0) close_m5 = cb[0];
   if(CopyBuffer(hEMA_M5, 0, 1, 1, mb) > 0) ma_m5 = mb[0];

   double dir_w1  = DirectionFromCloseMA(close_w1,  ma_w1);
   double dir_d1  = DirectionFromCloseMA(close_d1,  ma_d1);
   double dir_h4  = DirectionFromCloseMA(close_h4,  ma_h4);
   double dir_h1  = DirectionFromCloseMA(close_h1,  ma_h1);
   double dir_m15 = DirectionFromCloseMA(close_m15, ma_m15);
   double dir_m5  = DirectionFromCloseMA(close_m5,  ma_m5);

   double terrain = dir_w1*0.6 + dir_d1*0.4;
   double flow    = dir_h4*0.5 + dir_h1*0.5;
   double wave    = dir_m15*0.4 + dir_m5*0.6;

   return terrain*3.0 + flow*2.0 + wave*1.0;
  }

//+------------------------------------------------------------------+
// ── arrow routing (unchanged) ──
//+------------------------------------------------------------------+
void DrawSignalArrow(int idx, double score, double price)
  {
   StrongArrowBuf[idx] = EMPTY_VALUE;
   MidArrowBuf[idx]    = EMPTY_VALUE;
   WeakArrowBuf[idx]   = EMPTY_VALUE;

   if(score >= Score_Strong_Th)      StrongArrowBuf[idx] = price;
   else if(score >= Score_Mid_Th)    MidArrowBuf[idx]    = price;
   else if(score >= Score_Weak_Th)   WeakArrowBuf[idx]   = price;
  }

//+------------------------------------------------------------------+
// ── UI: heatmap bias -> panel color/label (presentation-only) ──
//+------------------------------------------------------------------+
color BiasColor(double bias)
  {
   if(bias > 4.0)       return TUTTO_ClrBullish;
   if(bias > 2.0)       return clrDeepSkyBlue;
   if(bias > -2.0)      return TUTTO_ClrNeutral;
   if(bias > -4.0)      return clrLightPink;
   return TUTTO_ClrBearish;
  }

string BiasLabel(double bias)
  {
   if(bias > 4.0)       return "BULL+";
   if(bias > 2.0)       return "BULL";
   if(bias > -2.0)      return "RANGE";
   if(bias > -4.0)      return "BEAR";
   return "BEAR+";
  }

//+------------------------------------------------------------------+
// OnCalculate
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
   int min_req = MA_Period + Swing_Lookback + 10;
   if(rates_total < min_req)
     {
      TuttoState_Show(g_mgr, TUTTO_ClrCalm, "WAIT");
      return 0;
     }

   //--- new-bar-only heavy work (MTF Heatmap, object drawing) — unchanged gating
   datetime cur_bar_time = time[rates_total - 2];
   bool new_bar = (cur_bar_time != g_last_bar);

   //--- EMA200 buffer fetch (unchanged)
   int start = (prev_calculated > 1) ? prev_calculated - 1 : min_req;
   int need  = rates_total - start + 5;
   double ema_buf[];
   ArraySetAsSeries(ema_buf, true);
   int got = CopyBuffer(hEMA, 0, 0, need, ema_buf);
   if(got <= 0) return prev_calculated;

   //--- main loop (unchanged)
   int loop_start = start;
   if(rates_total - loop_start > Lookback_Bars)
      loop_start = rates_total - Lookback_Bars;
   if(loop_start < min_req) loop_start = min_req;

   double last_score = 0;
   double last_price = 0;
   double last_sw_high = 0, last_sw_low = 0;

   for(int i = loop_start; i < rates_total - 1; i++)
     {
      int ema_pos = rates_total - 1 - i;
      if(ema_pos < 0 || ema_pos >= got) continue;
      double ma_val = ema_buf[ema_pos];
      if(ma_val <= 0) continue;

      double sw_high, sw_low;
      GetSwing(high, low, i, sw_high, sw_low);
      if(sw_high <= sw_low) { DrawSignalArrow(i, 0, 0); continue; }

      int prev_idx = i - 5;
      if(prev_idx < 0) prev_idx = 0;
      double prev_high = high[prev_idx];
      double prev_low  = low[prev_idx];

      double score = CalcTotalScore(close[i], sw_high, sw_low, ma_val, prev_high, prev_low);

      double arrow_price = low[i] - 10 * _Point;
      DrawSignalArrow(i, score, arrow_price);

      if(i == rates_total - 2)
        {
         last_score   = score;
         last_price   = close[i];
         last_sw_high = sw_high;
         last_sw_low  = sw_low;
        }
     }

   //--- new-bar-only: heatmap panel + FULL MODE TP/SL update (unchanged gating)
   if(new_bar)
     {
      g_last_bar = cur_bar_time;

      double bias = CalcHeatmapBias();

      bool full_mode = (last_score >= Score_Strong_Th);

      //--- STATE-tier indicator: dot + single short bias code only.
      //--- Score/RCI dropped from display per "prefer removing text
      //--- entirely" — full_mode is still computed unchanged above and
      //--- still gates the Entry/SL/TP block below exactly as before.
      if(ShowHeatmap)
         TuttoState_Show(g_mgr, BiasColor(bias), BiasLabel(bias));
      else
         TuttoState_Show(g_mgr, BiasColor(bias));   // dot only

      //--- Entry/SL/TP via shared Levels module (collision-avoided labels)
      if(full_mode && ShowTPSL)
        {
         double range = last_sw_high - last_sw_low;
         double entry = last_sw_low + 0.5 * range;
         double sl    = last_sw_low;
         double tp1   = last_sw_low + 1.618 * range;
         double tp2   = last_sw_low + 2.618 * range;
         double tp3   = last_sw_low + 4.236 * range;

         TuttoLevel levels[];
         ArrayResize(levels, 5);
         levels[0] = TuttoLevel_Make("ENTRY", entry, TUTTO_ClrEntry, "ENTRY", STYLE_SOLID);
         levels[1] = TuttoLevel_Make("SL",    sl,    TUTTO_ClrStop,  "SL",    STYLE_SOLID);
         levels[2] = TuttoLevel_Make("TP1",   tp1,   TUTTO_ClrTP1,   "TP1",   STYLE_DASH);
         levels[3] = TuttoLevel_Make("TP2",   tp2,   TUTTO_ClrTP2,   "TP2",   STYLE_DASH);
         levels[4] = TuttoLevel_Make("TP3",   tp3,   TUTTO_ClrTP3,   "TP3",   STYLE_DASH);

         TuttoLevels_Draw(g_mgr, levels);
        }
      else
        {
         TuttoLevel levels[];
         ArrayResize(levels, 5);
         levels[0] = TuttoLevel_Make("ENTRY", 0, TUTTO_ClrEntry, "ENTRY");
         levels[1] = TuttoLevel_Make("SL",    0, TUTTO_ClrStop,  "SL");
         levels[2] = TuttoLevel_Make("TP1",   0, TUTTO_ClrTP1,   "TP1");
         levels[3] = TuttoLevel_Make("TP2",   0, TUTTO_ClrTP2,   "TP2");
         levels[4] = TuttoLevel_Make("TP3",   0, TUTTO_ClrTP3,   "TP3");
         TuttoLevels_ClearAll(g_mgr, levels);
        }
     }

   ChartRedraw(0);
   return rates_total;
  }
