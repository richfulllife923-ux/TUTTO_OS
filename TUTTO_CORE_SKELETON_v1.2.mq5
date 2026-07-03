//+------------------------------------------------------------------+
//| TUTTO Geometric Field OS - Core Skeleton v1.2                    |
//| Current-Timeframe Structure Priority Clean Version                |
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

//-------------------------
// Inputs
//-------------------------
input int                InpMAPeriod       = 200;
input ENUM_MA_METHOD     InpMAMethod       = MODE_EMA;
input ENUM_APPLIED_PRICE InpMAPrice        = PRICE_CLOSE;

input int                InpSwingLookback  = 160;
input int                InpFractalDepth   = 3;
input int                InpSignalLookback = 60;
input double             InpBounceRatio    = 0.180;

input bool               InpShowZones      = true;
input bool               InpShowSignals    = true;
input bool               InpShowTPSL       = true;
input bool               InpShowLabels     = true;
input bool               InpShowStatePanel = true;

input color              InpMAColor        = clrDeepSkyBlue;
input color              InpLongColor      = clrLime;
input color              InpShortColor     = clrTomato;
input color              InpFibColor       = clrGold;
input color              InpZoneColor      = clrDarkSlateGray;
input color              InpTPColor        = clrAqua;
input color              InpSLColor        = clrOrangeRed;

input string             InpObjectPrefix   = "TUTTO_CORE_V12_";

//-------------------------
// Globals
//-------------------------
double   g_ma_buffer[];
int      g_ma_handle = INVALID_HANDLE;
datetime g_last_bar_time = 0;

struct SwingState
{
   bool     ready;
   double   last_high;
   double   prev_high;
   double   last_low;
   double   prev_low;
   datetime last_high_time;
   datetime prev_high_time;
   datetime last_low_time;
   datetime prev_low_time;
   bool     hh;
   bool     hl;
   bool     lh;
   bool     ll;
};

//-------------------------
// Object helpers
//-------------------------
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

void DrawHLine(const string suffix, const double price, const color clr, const ENUM_LINE_STYLE style, const int width, const string text)
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

void DrawZone(const string suffix, const datetime left_time, const datetime right_time, const double price_a, const double price_b, const color clr)
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

void DrawArrow(const string suffix, const datetime signal_time, const double price, const bool is_long)
{
   if(!InpShowSignals)
      return;

   string name = ObjName(suffix);

   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_ARROW, 0, signal_time, price);
   else
      ObjectMove(0, name, 0, signal_time, price);

   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, is_long ? 233 : 234);
   ObjectSetInteger(0, name, OBJPROP_COLOR, is_long ? InpLongColor : InpShortColor);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 4);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   SetCommonObjectStyle(name);
}

void DrawTextLabel(const string suffix, const datetime label_time, const double price, const string text, const color clr)
{
   if(!InpShowLabels)
      return;

   string name = ObjName(suffix);

   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_TEXT, 0, label_time, price);
   else
      ObjectMove(0, name, 0, label_time, price);

   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 10);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_CENTER);
   SetCommonObjectStyle(name);
}

void DrawPanel(const string text)
{
   if(!InpShowStatePanel)
      return;

   string name = ObjName("STATE_PANEL");

   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);

   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, 14);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, 18);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 10);
   ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   SetCommonObjectStyle(name);
}

//-------------------------
// Current timeframe swings
//-------------------------
bool IsPivotHigh(const double &high[], const int shift, const int rates_total)
{
   if(shift - InpFractalDepth < 1 || shift + InpFractalDepth >= rates_total)
      return false;

   double value = high[shift];

   for(int k = 1; k <= InpFractalDepth; k++)
   {
      if(high[shift - k] >= value)
         return false;
      if(high[shift + k] > value)
         return false;
   }

   return true;
}

bool IsPivotLow(const double &low[], const int shift, const int rates_total)
{
   if(shift - InpFractalDepth < 1 || shift + InpFractalDepth >= rates_total)
      return false;

   double value = low[shift];

   for(int k = 1; k <= InpFractalDepth; k++)
   {
      if(low[shift - k] <= value)
         return false;
      if(low[shift + k] < value)
         return false;
   }

   return true;
}

void ResetSwingState(SwingState &state)
{
   state.ready = false;
   state.last_high = 0.0;
   state.prev_high = 0.0;
   state.last_low = 0.0;
   state.prev_low = 0.0;
   state.last_high_time = 0;
   state.prev_high_time = 0;
   state.last_low_time = 0;
   state.prev_low_time = 0;
   state.hh = false;
   state.hl = false;
   state.lh = false;
   state.ll = false;
}

bool BuildCurrentTimeframeStructure(const double &high[], const double &low[], const datetime &time[], const int rates_total, SwingState &state)
{
   ResetSwingState(state);

   int high_count = 0;
   int low_count = 0;
   int max_shift = MathMin(InpSwingLookback, rates_total - InpFractalDepth - 1);

   if(max_shift <= InpFractalDepth + 2)
      return false;

   for(int shift = InpFractalDepth + 1; shift <= max_shift; shift++)
   {
      if(high_count < 2 && IsPivotHigh(high, shift, rates_total))
      {
         if(high_count == 0)
         {
            state.last_high = high[shift];
            state.last_high_time = time[shift];
         }
         else
         {
            state.prev_high = high[shift];
            state.prev_high_time = time[shift];
         }

         high_count++;
      }

      if(low_count < 2 && IsPivotLow(low, shift, rates_total))
      {
         if(low_count == 0)
         {
            state.last_low = low[shift];
            state.last_low_time = time[shift];
         }
         else
         {
            state.prev_low = low[shift];
            state.prev_low_time = time[shift];
         }

         low_count++;
      }

      if(high_count >= 2 && low_count >= 2)
         break;
   }

   if(high_count < 2 || low_count < 2)
      return false;

   state.hh = (state.last_high > state.prev_high);
   state.lh = (state.last_high < state.prev_high);
   state.hl = (state.last_low > state.prev_low);
   state.ll = (state.last_low < state.prev_low);
   state.ready = true;

   return true;
}

string HighLabel(const SwingState &state)
{
   if(state.hh)
      return "HH";
   if(state.lh)
      return "LH";
   return "EQH";
}

string LowLabel(const SwingState &state)
{
   if(state.hl)
      return "HL";
   if(state.ll)
      return "LL";
   return "EQL";
}

//-------------------------
// TUTTO geometry
//-------------------------
double FibPrice(const double swing_low, const double swing_high, const double ratio)
{
   return swing_low + (swing_high - swing_low) * ratio;
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

void DrawFibStructure(const datetime &time[], const int rates_total, const double swing_low, const double swing_high)
{
   double fib_0 = swing_low;
   double fib_1 = swing_high;
   double fib_050 = FibPrice(swing_low, swing_high, 0.500);
   double fib_0618 = FibPrice(swing_low, swing_high, 0.618);
   double fib_2618 = FibPrice(swing_low, swing_high, 2.618);
   double fib_4236 = FibPrice(swing_low, swing_high, 4.236);

   int left_shift = MathMin(InpSwingLookback, rates_total - 1);
   datetime left_time = time[left_shift];
   datetime right_time = time[0] + PeriodSeconds(_Period) * 24;

   DrawHLine("FIB_0", fib_0, InpFibColor, STYLE_DOT, 1, "TUTTO Fib 0");
   DrawHLine("FIB_1", fib_1, InpFibColor, STYLE_DOT, 1, "TUTTO Fib 1");
   DrawHLine("FIB_050", fib_050, clrWhite, STYLE_SOLID, 1, "TUTTO Fib 0.500");
   DrawHLine("FIB_0618", fib_0618, clrLime, STYLE_SOLID, 2, "TUTTO Fib 0.618");
   DrawHLine("FIB_2618", fib_2618, InpTPColor, STYLE_DASH, 2, "TUTTO Fib 2.618");
   DrawHLine("FIB_4236", fib_4236, clrMagenta, STYLE_DASH, 2, "TUTTO Fib 4.236");

   DrawZone("ZONE_050_0618", left_time, right_time, fib_050, fib_0618, InpZoneColor);
   DrawZone("ZONE_2618_4236", left_time, right_time, fib_2618, fib_4236, clrMidnightBlue);
}

void DrawTPSL(const bool is_long, const double tp_price, const double sl_price)
{
   if(!InpShowTPSL)
      return;

   DrawHLine(is_long ? "TP_LONG" : "TP_SHORT", tp_price, InpTPColor, STYLE_SOLID, 2, is_long ? "TUTTO LONG TP" : "TUTTO SHORT TP");
   DrawHLine(is_long ? "SL_LONG" : "SL_SHORT", sl_price, InpSLColor, STYLE_SOLID, 2, is_long ? "TUTTO LONG SL" : "TUTTO SHORT SL");
}

void DrawCurrentSignal(const double &open[], const double &high[], const double &low[], const double &close[], const datetime &time[], const SwingState &state)
{
   if(!InpShowSignals || !state.ready)
      return;

   double range = state.last_high - state.last_low;
   if(range <= 0.0)
      return;

   int shift = 1;
   double bounce_zone = range * InpBounceRatio;

   bool low_rebound = (low[shift] <= state.last_low + bounce_zone &&
                       close[shift] > open[shift] &&
                       close[shift] > close[shift + 1]);

   bool high_reject = (high[shift] >= state.last_high - bounce_zone &&
                       close[shift] < open[shift] &&
                       close[shift] < close[shift + 1]);

   bool ma_soft_long = (close[shift] >= g_ma_buffer[shift] || close[shift] > close[shift + 1]);
   bool ma_soft_short = (close[shift] <= g_ma_buffer[shift] || close[shift] < close[shift + 1]);

   bool long_signal = (state.hl && low_rebound && ma_soft_long);
   bool short_signal = (state.lh && high_reject && ma_soft_short);

   if(long_signal)
   {
      DrawArrow("ENTRY_LONG_" + IntegerToString((int)time[shift]), time[shift], low[shift] - range * 0.040, true);
      DrawTPSL(true, FibPrice(state.last_low, state.last_high, 2.618), state.last_low);
   }

   if(short_signal)
   {
      DrawArrow("ENTRY_SHORT_" + IntegerToString((int)time[shift]), time[shift], high[shift] + range * 0.040, false);
      DrawTPSL(false, FibPrice(state.last_low, state.last_high, -1.618), state.last_high);
   }
}

//-------------------------
// MT5 events
//-------------------------
int OnInit()
{
   if(InpMAPeriod < 2 || InpSwingLookback < 20 || InpFractalDepth < 1 || InpSignalLookback < 5)
      return INIT_PARAMETERS_INCORRECT;

   SetIndexBuffer(0, g_ma_buffer, INDICATOR_DATA);
   ArraySetAsSeries(g_ma_buffer, true);

   PlotIndexSetInteger(0, PLOT_LINE_COLOR, InpMAColor);
   PlotIndexSetInteger(0, PLOT_LINE_WIDTH, 2);
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   IndicatorSetString(INDICATOR_SHORTNAME, "TUTTO Core Skeleton v1.2 - Current TF Clean");

   g_ma_handle = iMA(_Symbol, _Period, InpMAPeriod, 0, InpMAMethod, InpMAPrice);
   if(g_ma_handle == INVALID_HANDLE)
      return INIT_FAILED;

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   DeleteTuttoObjects();

   if(g_ma_handle != INVALID_HANDLE)
      IndicatorRelease(g_ma_handle);
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
   int minimum_bars = MathMax(InpMAPeriod + 10, InpSwingLookback + InpFractalDepth + 10);
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

   SwingState state;
   if(!BuildCurrentTimeframeStructure(high, low, time, rates_total, state))
      return rates_total;

   DrawFibStructure(time, rates_total, state.last_low, state.last_high);

   DrawTextLabel("LAST_HIGH", state.last_high_time, state.last_high, HighLabel(state), InpFibColor);
   DrawTextLabel("LAST_LOW", state.last_low_time, state.last_low, LowLabel(state), InpFibColor);

   DrawCurrentSignal(open, high, low, close, time, state);

   double ma_prev = g_ma_buffer[10];
   double bias_score = BiasScore(close[1], g_ma_buffer[1], ma_prev);

   string state_text =
      "TUTTO Core Skeleton v1.2\n"
      "Current TF Structure Only\n"
      "Structure: " + HighLabel(state) + " / " + LowLabel(state) + "\n"
      "MA200 Bias Score: " + DoubleToString(bias_score, 2) + "\n"
      "MA Role: Soft Filter\n"
      "Long: HL + Swing-Low Rebound\n"
      "Short: LH + Swing-High Reject";

   DrawPanel(state_text);

   return rates_total;
}