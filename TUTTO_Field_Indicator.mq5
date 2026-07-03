#property indicator_chart_window
#property indicator_buffers 4
#property indicator_plots   4

#property indicator_label1 "MA200"
#property indicator_type1 DRAW_LINE
#property indicator_color1 clrDeepSkyBlue

#property indicator_label2 "EMA50"
#property indicator_type2 DRAW_LINE
#property indicator_color2 clrOrange

#property indicator_label3 "BUY"
#property indicator_type3 DRAW_ARROW
#property indicator_color3 clrLime

#property indicator_label4 "SELL"
#property indicator_type4 DRAW_ARROW
#property indicator_color4 clrRed

//---------------- buffers
double maBuffer[];
double emaBuffer[];
double buyBuffer[];
double sellBuffer[];

//---------------- handles
int maHandle;
int emaHandle;
int rsiHandle;

//---------------- settings
input int MA_Period = 200;
input int EMA_Period = 50;

//---------------- swing memory
double lastHigh = 0;
double lastLow  = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, maBuffer);
   SetIndexBuffer(1, emaBuffer);
   SetIndexBuffer(2, buyBuffer);
   SetIndexBuffer(3, sellBuffer);

   ArraySetAsSeries(maBuffer, true);
   ArraySetAsSeries(emaBuffer, true);
   ArraySetAsSeries(buyBuffer, true);
   ArraySetAsSeries(sellBuffer, true);

   PlotIndexSetInteger(2, PLOT_ARROW, 233);
   PlotIndexSetInteger(3, PLOT_ARROW, 234);

   maHandle  = iMA(NULL, 0, MA_Period, 0, MODE_SMA, PRICE_CLOSE);
   emaHandle = iMA(NULL, 0, EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   rsiHandle = iRSI(NULL, 0, 14, PRICE_CLOSE);

   if(maHandle == INVALID_HANDLE || emaHandle == INVALID_HANDLE || rsiHandle == INVALID_HANDLE)
      return INIT_FAILED;

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
bool SwingHigh(const double &high[], int i)
{
   return (high[i] > high[i+1] && high[i] > high[i-1]);
}

bool SwingLow(const double &low[], int i)
{
   return (low[i] < low[i+1] && low[i] < low[i-1]);
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
   if(rates_total < 210)
      return 0;

   CopyBuffer(maHandle, 0, 0, rates_total, maBuffer);
   CopyBuffer(emaHandle, 0, 0, rates_total, emaBuffer);

   double rsiBuffer[];
   ArraySetAsSeries(rsiBuffer, true);
   CopyBuffer(rsiHandle, 0, 0, rates_total, rsiBuffer);

   for(int i = rates_total - 3; i >= 1; i--)
   {
      buyBuffer[i]  = EMPTY_VALUE;
      sellBuffer[i] = EMPTY_VALUE;

      if(SwingHigh(high, i))
         lastHigh = high[i];

      if(SwingLow(low, i))
         lastLow = low[i];

      if(lastHigh == 0 || lastLow == 0)
         continue;

      double rsi = rsiBuffer[i];

      bool trendUp   = close[i] > maBuffer[i] && emaBuffer[i] > maBuffer[i];
      bool trendDown = close[i] < maBuffer[i] && emaBuffer[i] < maBuffer[i];

      bool buyOK  = rsi < 70;
      bool sellOK = rsi > 30;

      if(trendUp && buyOK)
         buyBuffer[i] = low[i] - (Point * 15);

      if(trendDown && sellOK)
         sellBuffer[i] = high[i] + (Point * 15);
   }

   return rates_total;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(maHandle);
   IndicatorRelease(emaHandle);
   IndicatorRelease(rsiHandle);
}