//+------------------------------------------------------------------+
//| TUTTO_ENTRY_INDICATOR_v2 - TUTTO FIBO CORE VERSION             |
//| Arrow + Zone + Fibonacci Structure (Non-repaint core)         |
//+------------------------------------------------------------------+
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   2

//---- BUY
#property indicator_label1  "BUY"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrLime
#property indicator_width1  2

//---- SELL
#property indicator_label2  "SELL"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrRed
#property indicator_width2  2

double BuyBuffer[];
double SellBuffer[];

//---- inputs
input int ATR_Period = 14;
input double Zone_Multiplier = 1.5;
input bool DebugMode = true;

//---- ATR
int atrHandle;

//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, BuyBuffer, INDICATOR_DATA);
   SetIndexBuffer(1, SellBuffer, INDICATOR_DATA);

   ArraySetAsSeries(BuyBuffer, true);
   ArraySetAsSeries(SellBuffer, true);

   PlotIndexSetInteger(0, PLOT_ARROW, 241); // ▲安定版
   PlotIndexSetInteger(1, PLOT_ARROW, 242); // ▼安定版

   atrHandle = iATR(_Symbol, _Period, ATR_Period);

   if(atrHandle == INVALID_HANDLE)
      return INIT_FAILED;

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
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
   if(rates_total < ATR_Period + 10)
      return 0;

   double atr[];
   ArraySetAsSeries(atr, true);

   if(CopyBuffer(atrHandle, 0, 0, rates_total, atr) <= 0)
      return 0;

   int start = rates_total - 3;
   if(start < 2) return 0;

   for(int i = start; i >= 2; i--)
   {
      BuyBuffer[i]  = EMPTY_VALUE;
      SellBuffer[i] = EMPTY_VALUE;

      double zone = atr[i] * Zone_Multiplier;

      // =========================
      // TUTTO FIBO STRUCTURE LOGIC
      // =========================

      double move = high[i] - low[i-1];
      double fib0   = low[i];
      double fib50  = low[i] + move * 0.5;
      double fib618 = low[i] + move * 0.618;
      double fib1   = high[i];
      double fib2618= high[i] + move * 1.618;

      // =========================
      // BUY CONDITION (STRUCTURE)
      // =========================
      if(close[i] > close[i-1] && close[i-1] > close[i-2])
      {
         BuyBuffer[i] = low[i] - zone;

         DrawZone(time[i], fib0, fib618, clrGreen, "TUTTO_BUY_" + IntegerToString(i));
      }

      // =========================
      // SELL CONDITION
      // =========================
      if(close[i] < close[i-1] && close[i-1] < close[i-2])
      {
         SellBuffer[i] = high[i] + zone;

         DrawZone(time[i], fib618, fib0, clrRed, "TUTTO_SELL_" + IntegerToString(i));
      }

      // =========================
      // DEBUG MODE (絶対表示保証)
      // =========================
      if(DebugMode && i == start)
      {
         BuyBuffer[i] = low[i] - zone;
      }
   }

   return rates_total;
}

//+------------------------------------------------------------------+
//| Zone Draw                                                       |
//+------------------------------------------------------------------+
void DrawZone(datetime t,
              double top,
              double bottom,
              color clr,
              string name)
{
   if(ObjectFind(0, name) >= 0) return;

   ObjectCreate(0, name, OBJ_RECTANGLE, 0,
                t, top,
                t + PeriodSeconds()*3, bottom);

   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
}