//+------------------------------------------------------------------+
//| TUTTO_CORE_SKELETON_v1.3                                         |
//| Entry / TP / SL Visual Trade Structure System                    |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window
#property indicator_buffers 1
#property indicator_plots   1

#property indicator_label1  "TUTTO 200MA"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDeepSkyBlue
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

input int                InpMAPeriod        = 200;
input ENUM_MA_METHOD     InpMAMethod        = MODE_EMA;
input ENUM_APPLIED_PRICE InpMAPrice         = PRICE_CLOSE;

input int                InpSwingLookback   = 80;
input int                InpSignalLookback  = 60;
input double             InpSLBufferRatio   = 0.05;

input bool               InpShowZones       = true;
input bool               InpShowSignals     = true;
input bool               InpShowTPSL        = true;
input bool               InpShowComment     = true;

input color              InpMAColor         = clrDeepSkyBlue;
input color              InpLongColor       = clrLime;
input color              InpShortColor      = clrRed;
input color              InpFibColor        = clrGold;
input color              InpFibKeyColor     = clrLime;
input color              InpZoneColor       = clrDarkSlateGray;
input color              InpTP1Color        = clrWhite;
input color              InpTP2Color        = clrAqua;
input color              InpTP3Color        = clrMagenta;
input color              InpSLColor         = clrOrangeRed;

input string             InpObjectPrefix    = "TUTTO_V13_";

double   g_ma_buffer[];
int      g_ma_handle = INVALID_HANDLE;
datetime g_last_bar_time = 0;

//+------------------------------------------------------------------+
//| Object helpers                                                   |
//+------------------------------------------------------------------+
string ObjName(const string suffix)
{
   return InpObjectPrefix + suffix;
}

void DeleteTuttoObjects()
{
   int total = ObjectsTotal(0, 0, -1);

   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, InpObjectPrefix) == 0)
         ObjectDelete(0, name);
   }
}

void SetCommonObjectStyle(const string name)
{
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

void DrawHLine(const string suffix,
               const double price,
               const color clr,
               const ENUM_LINE_STYLE style,
               const int width,
               const string text)
{
   string name = ObjName(suffix);

   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);

   ObjectSetDouble(0, name, OBJPROP_PRICE, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   SetCommonObjectStyle(name);
}

void DrawZone(const string suffix,
              const datetime left_time,
              const datetime right_time,
              const double price_a,
              const double price_b,
              const color clr)
{
   if(!InpShowZones)
      return;

   double top = MathMax(price_a, price_b);
   double bottom = MathMin(price_a, price_b);
   string name = ObjName(suffix);

   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, left_time, top, right_time, bottom);
   else
   {
      ObjectMove(0, name, 0, left_time, top);
      ObjectMove(0, name, 1, right_time, bottom);
   }

   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   SetCommonObjectStyle(name);
}

void DrawArrow(const string suffix,
               const datetime signal_time,
               const double price,
               const bool is_long)
{
   if(!InpShowSignals)
      return;

   string name = ObjName(suffix);

   if(ObjectFind(0, name) >= 0)
      return;

   ObjectCreate(0, name, OBJ_ARROW, 0, signal_time, price);
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, is_long ? 233 : 234);
   ObjectSetInteger(0, name, OBJPROP_COLOR, is_long ? InpLongColor : InpShortColor);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 4);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   SetCommonObjectStyle(name);
}

void DrawText(const string suffix,
              const datetime text_time,
              const double price,
              const string text,
              const color clr)
{
   string name = ObjName(suffix);

   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TEXT, 0, text_time, price);
   else
      ObjectMove(0, name, 0, text_time, price);

   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 10);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_CENTER);
   SetCommonObjectStyle(name);
}

//+------------------------------------------------------------------+
//| Swing / geometry                                                 |
//+------------------------------------------------------------------+
bool GetCurrentTimeframeSwings(const double &high[],
                               const double &low[],
                               const int rates_total,
                               double &swing_high,
                               double &swing_low,
                               int &swing_high_index,
                               int &swing_low_index)
{
   swing_high = 0.0;
   swing_low = 0.0;
   swing_high_index = -1;
   swing_low_index = -1;

   int lookback = MathMin(InpSwingLookback, rates_total - 2);
   if(lookback < 5)
      return false;

   swing_high_index = ArrayMaximum(high, 1, lookback);
   swing_low_index = ArrayMinimum(low, 1, lookback);

   if(swing_high_index < 0 || swing_low_index < 0)
      return false;

   swing_high = high[swing_high_index];
   swing_low = low[swing_low_index];

   if(swing_high <= 0.0 || swing_low <= 0.0)
      return false;

   if(swing_high <= swing_low)
      return false;

   return true;
}

bool IsUpStructure(const int swing_high_index, const int swing_low_index)
{
   return (swing_low_index > swing_high_index);
}

double FibPrice(const double origin, const double target, const double ratio)
{
   return origin + (target - origin) * ratio;
}

double BiasScore(const double close_price, const double ma_now, const double ma_prev)
{
   double score = 0.0;

   if(close_price > ma_now)
      score += 0.50;
   else
      score -= 0.50;

   if(ma_now > ma_prev)
      score += 0.50;
   else if(ma_now < ma_prev)
      score -= 0.50;

   return score;
}

//+------------------------------------------------------------------+
//| Drawing                                                          |
//+------------------------------------------------------------------+
void DrawFibAndTradeStructure(const datetime &time[],
                              const int rates_total,
                              const double swing_high,
                              const double swing_low,
                              const int swing_high_index,
                              const int swing_low_index,
                              const bool up_structure)
{
   double origin = up_structure ? swing_low : swing_high;
   double target = up_structure ? swing_high : swing_low;
   double range = MathAbs(swing_high - swing_low);
   double sl_buffer = range * InpSLBufferRatio;

   double fib_0 = FibPrice(origin, target, 0.000);
   double fib_050 = FibPrice(origin, target, 0.500);
   double fib_0618 = FibPrice(origin, target, 0.618);
   double fib_1 = FibPrice(origin, target, 1.000);
   double fib_2618 = FibPrice(origin, target, 2.618);
   double fib_4236 = FibPrice(origin, target, 4.236);

   double sl = up_structure ? swing_low - sl_buffer : swing_high + sl_buffer;

   int left_shift = MathMin(InpSwingLookback, rates_total - 1);
   datetime left_time = time[left_shift];
   datetime right_time = time[0] + PeriodSeconds(PERIOD_CURRENT) * 24;

   DrawHLine("FIB_0", fib_0, InpFibColor, STYLE_DOT, 1, "TUTTO Fib 0.0");
   DrawHLine("FIB_050", fib_050, clrWhite, STYLE_SOLID, 1, "TUTTO Fib 0.5");
   DrawHLine("FIB_0618", fib_0618, InpFibKeyColor, STYLE_SOLID, 3, "TUTTO Fib 0.618");
   DrawHLine("FIB_1", fib_1, InpFibColor, STYLE_DOT, 1, "TUTTO Fib 1.0");

   DrawHLine("TP1", fib_1, InpTP1Color, STYLE_SOLID, 2, "TP1 / Fib 1.0");
   DrawHLine("TP2", fib_2618, InpTP2Color, STYLE_DASH, 2, "TP2 / Fib 2.618");
   DrawHLine("TP3", fib_4236, InpTP3Color, STYLE_DASH, 3, "TP3 / Fib 4.236");
   DrawHLine("SL", sl, InpSLColor, STYLE_SOLID, 3, "SL");

   DrawZone("ENTRY_ZONE_050_0618", left_time, right_time, fib_050, fib_0618, InpZoneColor);

   DrawText("SWING_HIGH", time[swing_high_index], swing_high, "swingHigh", InpFibColor);
   DrawText("SWING_LOW", time[swing_low_index], swing_low, "swingLow", InpFibColor);
}

void DrawSignalIfNeeded(const double &open[],
                        const double &high[],
                        const double &low[],
                        const double &close[],
                        const datetime &time[],
                        const double swing_high,
                        const double swing_low,
                        const bool up_structure)
{
   int shift = 1;
   double origin = up_structure ? swing_low : swing_high;
   double target = up_structure ? swing_high : swing_low;

   double fib_050 = FibPrice(origin, target, 0.500);
   double fib_0618 = FibPrice(origin, target, 0.618);

   double zone_top = MathMax(fib_050, fib_0618);
   double zone_bottom = MathMin(fib_050, fib_0618);

   bool in_zone = (close[shift] >= zone_bottom && close[shift] <= zone_top);
   bool bullish_rebound = (close[shift] > open[shift] && close[shift] > close[shift + 1]);
   bool bearish_reject = (close[shift] < open[shift] && close[shift] < close[shift + 1]);

   double range = MathAbs(swing_high - swing_low);
   if(range <= 0.0)
      return;

   if(up_structure && in_zone && bullish_rebound)
   {
      DrawArrow("ENTRY_LONG_" + IntegerToString((int)time[shift]),
                time[shift],
                low[shift] - range * 0.040,
                true);
   }

   if(!up_structure && in_zone && bearish_reject)
   {
      DrawArrow("ENTRY_SHORT_" + IntegerToString((int)time[shift]),
                time[shift],
                high[shift] + range * 0.040,
                false);
   }
}

//+------------------------------------------------------------------+
//| MT5 events                                                       |
//+------------------------------------------------------------------+
int OnInit()
{
   if(InpMAPeriod < 2 ||
      InpSwingLookback < 10 ||
      InpSignalLookback < 1 ||
      InpSLBufferRatio <= 0.0)
   {
      return INIT_PARAMETERS_INCORRECT;
   }

   SetIndexBuffer(0, g_ma_buffer, INDICATOR_DATA);
   ArraySetAsSeries(g_ma_buffer, true);

   PlotIndexSetInteger(0, PLOT_LINE_COLOR, InpMAColor);
   PlotIndexSetInteger(0, PLOT_LINE_WIDTH, 2);
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   IndicatorSetString(INDICATOR_SHORTNAME, "TUTTO_CORE_SKELETON_v1.3");

   g_ma_handle = iMA(_Symbol, PERIOD_CURRENT, InpMAPeriod, 0, InpMAMethod, InpMAPrice);
   if(g_ma_handle == INVALID_HANDLE)
      return INIT_FAILED;

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   DeleteTuttoObjects();

   if(g_ma_handle != INVALID_HANDLE)
      IndicatorRelease(g_ma_handle);

   Comment("");
}

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   int minimum_bars = MathMax(InpMAPeriod + 5, InpSwingLookback + 5);
   if(rates_total < minimum_bars)
      return 0;

   ArraySetAsSeries(time, true);
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);

   int copied = CopyBuffer(g_ma_handle, 0, 0, rates_total, g_ma_buffer);
   if(copied <= 0)
      return prev_calculated;

   if(prev_calculated == 0)
      DeleteTuttoObjects();

   if(g_last_bar_time != time[1])
   {
      g_last_bar_time = time[1];
      DeleteTuttoObjects();
   }

   double swing_high = 0.0;
   double swing_low = 0.0;
   int swing_high_index = -1;
   int swing_low_index = -1;

   bool swing_ok = GetCurrentTimeframeSwings(high,
                                             low,
                                             rates_total,
                                             swing_high,
                                             swing_low,
                                             swing_high_index,
                                             swing_low_index);

   if(!swing_ok)
   {
      Comment("TUTTO_CORE_SKELETON_v1.3\nSwing not ready\nMTF: disabled");
      return rates_total;
   }

   bool up_structure = IsUpStructure(swing_high_index, swing_low_index);

   DrawFibAndTradeStructure(time,
                            rates_total,
                            swing_high,
                            swing_low,
                            swing_high_index,
                            swing_low_index,
                            up_structure);

   DrawSignalIfNeeded(open,
                      high,
                      low,
                      close,
                      time,
                      swing_high,
                      swing_low,
                      up_structure);

   double current_price = close[1];
   double ma_now = g_ma_buffer[1];
   double ma_prev = g_ma_buffer[MathMin(10, rates_total - 1)];
   double bias_score = BiasScore(current_price, ma_now, ma_prev);

   if(InpShowComment)
   {
      Comment(
         "TUTTO_CORE_SKELETON_v1.3\n",
         "TF: ", EnumToString((ENUM_TIMEFRAMES)_Period), "\n",
         "MTF: disabled\n",
         "Structure: ", up_structure ? "UP swingLow -> swingHigh" : "DOWN swingHigh -> swingLow", "\n",
         "swingHigh: ", DoubleToString(swing_high, _Digits), "\n",
         "swingLow : ", DoubleToString(swing_low, _Digits), "\n",
         "MA200 bias: ", DoubleToString(bias_score, 2), "\n",
         "MA role: soft bias only\n",
         "Entry zone: Fib 0.5 - 0.618\n",
         "TP1/TP2/TP3 and SL visible"
      );
   }

   return rates_total;
}